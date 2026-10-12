#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
kmomentum_test_dir=$(mktemp -d /tmp/KMomentum-tests.XXXXXX)
swiftc -module-cache-path "$kmomentum_test_dir/cache" Shared/HabitRules.swift Shared/WorkoutDomain.swift Shared/PlanText.swift Shared/WidgetSnapshot.swift Tests/main.swift -o "$kmomentum_test_dir/rules"
"$kmomentum_test_dir/rules"
swiftc -module-cache-path "$kmomentum_test_dir/cache" Shared/HabitRules.swift Shared/WidgetSnapshot.swift Tests/LockScreen.swift -o "$kmomentum_test_dir/lock-screen"
"$kmomentum_test_dir/lock-screen"
swiftc -module-cache-path "$kmomentum_test_dir/cache" Shared/HabitRules.swift Tests/Fixtures/ModelsV1.swift Tests/MigrationV1.swift -o "$kmomentum_test_dir/v1"
swiftc -module-cache-path "$kmomentum_test_dir/cache" Shared/HabitRules.swift Shared/WorkoutDomain.swift Shared/PlanText.swift KMomentum/Models.swift Tests/MigrationV2.swift -o "$kmomentum_test_dir/v2"
"$kmomentum_test_dir/v1" "$kmomentum_test_dir/migration.store"
"$kmomentum_test_dir/v2" "$kmomentum_test_dir/migration.store"
