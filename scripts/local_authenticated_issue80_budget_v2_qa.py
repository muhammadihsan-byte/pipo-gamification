#!/usr/bin/env python3
"""Signed local-only Budget CAS V2 test, plus old-client breakage proof.

This runs after local_authenticated_issue80_cas_qa.py in the SAME disposable
Supabase CLI stack. Real user JWTs for owner-specific Data API calls; admin
key only provisions fictional loopback Auth users. No production URL allowed.
"""
from __future__ import annotations
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal
from threading import Barrier
import time
import uuid

from local_authenticated_global_v1_qa import (
    api, local_stack_config, loopback_only, make_user, require,
)
from local_authenticated_issue80_cas_qa import run_sql

def request(base, anon, token, request_id, goal_id, revision, amount,
            items, reviewed=False):
    return api(
        base,anon,"/rest/v1/rpc/pipo_apply_plan_budget_v2",
        bearer=token,method="POST",
        body={
            "p_request_id":request_id, "p_goal_id":goal_id,
            "p_expected_revision":revision, "p_target_amount":amount,
            "p_target_date":"2030-01-01T00:00:00+00:00",
            "p_rhythm":"weekly","p_preferred_saving_day":2,
            "p_planned_contribution_override":25,
            "p_items":items, "p_budget_import_confirmed":reviewed,
        },
    )
def read(base,anon,token,goal):
    return api(base,anon,"/rest/v1/rpc/pipo_read_plan_budget_v2",
               method="POST",bearer=token,body={"p_goal_id":goal})

def main():
    cfg=local_stack_config() # REFUSES any non-loopback URL.
    base,db,anon,service=(cfg[k] for k in ("API_URL","DB_URL","ANON_KEY","SERVICE_ROLE_KEY"))
    loopback_only(base,"API_URL")
    loopback_only(db,"DB_URL")
    run_sql(db,"supabase/proposals/issue_80_budget_cas_v2_REVIEW_ONLY.sql",file=True)
    run_sql(db,"NOTIFY pgrst, 'reload schema'")
    time.sleep(1.0)
    alice,ajwt=make_user(base,service,anon,"elaine+budgetcasqa@local.test")
    bob,bjwt=make_user(base,service,anon,"fred+budgetcasqa@local.test")
    goal=str(uuid.uuid4())
    code,rows=api(base,anon,"/rest/v1/saving_goals",
        method="POST",bearer=ajwt,prefer="return=representation",
        body={
            "id":goal,"title":"Budget CAS goal","category":"trip",
            "target_amount":300,"target_date":"2030-01-01T00:00:00+00:00",
            "currency_code":"IDR","budget_snapshot_state":"synced"
        })
    require(code==201 and isinstance(rows,list) and len(rows)==1,
            f"Signed create failed {code} {rows}")
    require(rows[0]["user_id"]==alice and
            rows[0]["budget_snapshot_state"]=="needs_review",
            "Client bypassed mandatory initial budget review")
    code,start=read(base,anon,ajwt,goal)
    require(code==200 and isinstance(start,dict)
            and start["budget_snapshot_state"]=="needs_review"
            and start["items"]==[],"Owner's initial budget snapshot incorrect")
    code,foreign=read(base,anon,bjwt,goal)
    require(code in (401,403,404) and isinstance(foreign,dict)
            and foreign.get("code")=="42501","Bob read Alice's private goal/budget")
    items=[
        {"id":str(uuid.uuid4()),"title":"Train","amount":250,"is_completed":False},
        {"id":str(uuid.uuid4()),"title":"Hotel","amount":150,"is_completed":True}
    ]
    request_id=str(uuid.uuid4())
    code,blocked=request(base,anon,ajwt,str(uuid.uuid4()),goal,0,400,items,False)
    require(code>=400 and isinstance(blocked,dict)
            and blocked.get("code")=="22023",
            "Unreviewed legacy cloud budget was silently replaced")
    code,first=request(base,anon,ajwt,request_id,goal,0,400,items,True)
    require(code==200 and isinstance(first,dict)
            and first["status"]=="applied"
            and first["accepted_revision"]==1
            and first["budget_snapshot_state"]=="synced"
            and len(first["items"])==2
            and first["items"][0]["title"]=="Train"
            and first["items"][1]["is_completed"] is True,
            f"Atomic budget V2 initial apply failed: {code} {first}")
    code,replay=request(base,anon,ajwt,request_id,goal,0,400,items,True)
    require(code==200 and replay==first,"Identical request replay duplicated budget CAS")
    code,stale=request(base,anon,ajwt,str(uuid.uuid4()),goal,0,800,[],True)
    require(code==200 and isinstance(stale,dict)
            and stale.get("status")=="conflict"
            and stale.get("current_revision")==1,
            "Stale budget update silently replaced new target/allocations")
    changed=[dict(items[0],amount=200),dict(items[1],amount=200)]
    code,spoof=request(base,anon,ajwt,request_id,goal,0,400,changed,True)
    require(code>=400 and isinstance(spoof,dict)
            and spoof.get("code")=="23505","UUID reuse with changed budget accepted")
    code,bad=request(base,anon,ajwt,str(uuid.uuid4()),goal,1,400,
                     [dict(items[0],amount=399)],False)
    require(code>=400 and isinstance(bad,dict)
            and bad.get("code")=="22023","Mismatched budget total accepted")
    code,bad=request(base,anon,ajwt,str(uuid.uuid4()),goal,1,400,
                     [dict(items[0],amount=399.5)],False)
    require(code>=400 and isinstance(bad,dict)
            and bad.get("code")=="22023","Fractional IDR item accepted")
    code,blocked=request(base,anon,bjwt,str(uuid.uuid4()),goal,1,500,[],True)
    require(code in (401,403,404) and isinstance(blocked,dict)
            and blocked.get("code")=="42501",
            "Foreign signed user mutated another account's budget")
    code,result=read(base,anon,ajwt,goal)
    require(code==200 and isinstance(result,dict) and
            result["plan_revision"]==1 and len(result["items"])==2
            and Decimal(str(result["target_amount"]))==Decimal("400"),
            "Invalid calls changed current budget snapshot")

    # Old signed clients do UPSERT (onConflict:id, merge-duplicates).
    # It MUST be denied after secure CAS cutover, not silently misreported
    # as persisted. This is the upgrade/compatibility release blocker.
    code,old=api(
        base,anon,"/rest/v1/saving_goals?on_conflict=id",
        method="POST",bearer=ajwt,prefer="resolution=merge-duplicates",
        body=[{"id":goal,"user_id":alice,"title":"Legacy",
               "category":"trip","target_amount":999,
               "currency_code":"IDR",
               "target_date":"2030-01-01T00:00:00+00:00"}]
    )
    require(code>=400 and isinstance(old,dict)
            and old.get("code")=="42501",
            f"Legacy UPSERT was not clearly denied: {code} {old}")
    code,old_rpc=api(base,anon,"/rest/v1/rpc/pipo_apply_plan_revision_v1",
        method="POST",bearer=ajwt,body={
            "p_request_id":str(uuid.uuid4()),"p_goal_id":goal,
            "p_expected_revision":1,"p_target_amount":500,
            "p_target_date":"2030-01-01T00:00:00+00:00",
            "p_rhythm":"weekly","p_preferred_saving_day":2,
            "p_planned_contribution_override":25,
        })
    require(code>=400 and isinstance(old_rpc,dict)
            and old_rpc.get("code")=="42501",
            f"Legacy target-only V1 CAS bypass remains: {code} {old_rpc}")
    # Replay and old-client errors never mutate XP/history.
    entry=str(uuid.uuid4())
    code,event=api(base,anon,"/rest/v1/saving_transactions",
        method="POST",bearer=ajwt,prefer="return=representation",
        body={"id":entry,"goal_id":goal,"amount":50,"xp_earned":300,
              "date":"2026-11-20T00:00:00Z"})
    require(code==201 and isinstance(event,list) and
            event[0]["xp_earned"]==300, "Deposit/XP insert broken after budget V2")

    # Two parallel SIGNED HTTP RPCs from the same revision: exactly one wins.
    barrier=Barrier(2,timeout=10)
    proposed=[(str(uuid.uuid4()),450,[
                  {"id":str(uuid.uuid4()),"title":"Beach","amount":450,"is_completed":False}]),
              (str(uuid.uuid4()),470,[
                  {"id":str(uuid.uuid4()),"title":"Hike","amount":470,"is_completed":False}])]
    def write(entry):
        barrier.wait()
        return request(base,anon,ajwt,entry[0],goal,1,entry[1],entry[2],False)
    with ThreadPoolExecutor(max_workers=2) as executor:
        outcomes=list(executor.map(write,proposed))
    winner=[x for c,x in outcomes if c==200 and isinstance(x,dict)
            and x.get("status")=="applied"]
    conflict=[x for c,x in outcomes if c==200 and isinstance(x,dict)
              and x.get("status")=="conflict"]
    require(len(winner)==1 and len(conflict)==1 and
            winner[0].get("accepted_revision")==2 and
            conflict[0].get("current_revision")==2,
            f"Parallel budget updates not serialized: {outcomes}")
    code,last=read(base,anon,ajwt,goal)
    require(code==200 and last["plan_revision"]==2
            and len(last["items"])==1
            and Decimal(str(last["target_amount"]))
               ==Decimal(str(last["items"][0]["amount"]))
            and last["items"][0]["title"] in {"Beach","Hike"},
            "Parallel budget/target separated or partially overwritten")
    print("PASS: signed Auth A/B atomic budget CAS V2, user-reviewed import, "
          "UUID replay, stale conflict, currency, XP, old-client UPSERT denial "
          "and parallel target+budget updates (LOCAL ONLY)")
if __name__=="__main__":
    main()
