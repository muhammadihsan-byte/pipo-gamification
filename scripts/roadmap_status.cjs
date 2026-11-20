// Trusted-base workflow: never load code from the pull request being processed.
// Only move an *existing* roadmap issue from Todo/Backlog to In Progress.
// An issue's Done state is governed by GitHub's native "Item closed" workflow.
"use strict";

const PROJECT_OWNER = "muhammadihsan-byte";
const PROJECT_NUMBER = 1;

function issueNumberForBranch(branch) {
  if (typeof branch !== "string") return null;
  const match = /^(?:feat|fix|chore|refactor|test|docs)\/pipo-([1-9][0-9]{0,5})-[a-z0-9][a-z0-9-]*$/.exec(branch);
  return match ? Number(match[1]) : null;
}

async function syncRoadmapStatus({ github, context, core }) {
  const pull = context.payload.pull_request;
  const repo = context.repo;
  const expectedRepository = repo.owner + "/" + repo.repo;
  if (!pull || pull.head?.repo?.full_name !== expectedRepository) {
    core.info("No trusted same-repository pull request. Skipping.");
    return "skipped-untrusted";
  }

  const number = issueNumberForBranch(pull.head.ref);
  if (!number) {
    core.info("No unambiguous issue number in branch. Skipping: " + pull.head.ref);
    return "skipped-unmapped";
  }

  // Rely on the actual GitHub issue and project membership, not the PR body,
  // which may mention unrelated tickets or partial features.
  const query = [
    "query($owner:String!,$name:String!,$issue:Int!,$projectOwner:String!,$projectNumber:Int!){",
    " repository(owner:$owner,name:$name){",
    "   issue(number:$issue){ id state projectItems(first:100){nodes{",
    "     id project{id} fieldValueByName(name:\"Status\"){",
    "       ... on ProjectV2ItemFieldSingleSelectValue{name}",
    "     }",
    "   }}}",
    " }",
    " user(login:$projectOwner){projectV2(number:$projectNumber){",
    "   id field(name:\"Status\"){",
    "     ... on ProjectV2SingleSelectField{id options{id name}}",
    "   }",
    " }}",
    "}"
  ].join("\n");
  const data = await github.graphql(query, {
    owner: repo.owner, name: repo.repo, issue: number,
    projectOwner: PROJECT_OWNER, projectNumber: PROJECT_NUMBER
  });
  const issue = data.repository?.issue;
  const project = data.user?.projectV2;
  if (!issue || issue.state !== "OPEN") {
    core.info("Issue #" + number + " is missing or closed. No changes.");
    return "skipped-closed";
  }
  if (!project?.id || !project.field?.id) {
    throw new Error("Pipo Project #1 or its Status field is unavailable.");
  }
  const item = issue.projectItems?.nodes?.find(x => x?.project?.id === project.id);
  if (!item) {
    core.notice("Issue #" + number + " is not on Pipo Project #1; enable Auto-add or add it first.");
    return "skipped-not-in-project";
  }
  const current = item.fieldValueByName?.name?.trim() ?? "";
  if (current && !["todo", "to do", "backlog"].includes(current.toLowerCase())) {
    core.info("Issue #" + number + " is already " + current + "; leaving it unchanged.");
    return "skipped-already-active";
  }
  const choice = project.field.options.find(x => x.name.trim().toLowerCase() === "in progress");
  if (!choice) throw new Error("In Progress is not an available Pipo Project #1 Status.");
  const mutation = [
    "mutation($project:ID!,$item:ID!,$field:ID!,$choice:String!){",
    " updateProjectV2ItemFieldValue(input:{",
    "   projectId:$project,itemId:$item,fieldId:$field,",
    "   value:{singleSelectOptionId:$choice}",
    " }){projectV2Item{id}}",
    "}"
  ].join("\n");
  await github.graphql(mutation, {
    project: project.id, item: item.id,
    field: project.field.id, choice: choice.id
  });
  core.info("Issue #" + number + " changed from " + (current || "empty") + " to In Progress.");
  return "updated";
}

module.exports = { issueNumberForBranch, syncRoadmapStatus };
