# This script runs only in the disposable QA checkout.
from pathlib import Path
p = Path('Pipo/App/PipoApp.swift')
s = p.read_text().replace('            RootView()', '''            RootView(initialAuthState: ProcessInfo.processInfo.arguments.contains("-SavingJourneyUITest") ? .authenticated : .unauthenticated)
                .onAppear {
                    if ProcessInfo.processInfo.arguments.contains("-SavingJourneyUITest") {
                        let enabled = UIAccessibility.isReduceMotionEnabled
                        try? String(enabled).write(to: URL.documentsDirectory.appendingPathComponent("saving-reduce-motion.txt"),
                                                   atomically: true, encoding: .utf8)
                    }
                }''')
p.write_text(s)
p = Path('Pipo.xcodeproj/project.pbxproj')
s = p.read_text().replace('com.apple.product-type.bundle.unit-test','com.apple.product-type.bundle.ui-testing')
s = s.replace('BUNDLE_LOADER = "$(TEST_HOST)";','TEST_TARGET_NAME = Pipo;')
s = s.replace('TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Pipo.app/Pipo";','')
p.write_text(s)
for source in Path('PipoTests').glob('*.swift'):
    source.write_text('// Simulator UI test target in QA checkout\n')
Path('PipoTests/GroupPlanJourneyTests.swift').write_text(Path('verification/SavingFlowUITests.swift').read_text())
