allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Force every Flutter plugin module (flutter_secure_storage, mobile_scanner,
// flutter_local_notifications, etc.) to compile against Java 17.
// Several plugins still declare sourceCompatibility/targetCompatibility = 1.8
// inside their own build.gradle, which makes javac emit:
//   "source/target value 8 is obsolete and will be removed in a future release"
//
// Two earlier attempts failed and the reasons are worth recording:
//
//   1. Configuring `android.compileOptions` from `plugins.withId { ... }`
//      raised "sourceCompatibility has been finalized" — AGP 8.x locks the
//      DSL extension shortly after the plugin module is evaluated.
//
//   2. Configuring the `JavaCompile` task directly from a root-level
//      `subprojects { tasks.withType<JavaCompile>().configureEach { ... } }`
//      block looked correct but lost the configuration race: AGP wires the
//      task's source/target compatibility from `compileOptions` in the
//      plugin module's own `afterEvaluate`, which runs *after* our root
//      `configureEach` callback. AGP's value won, so javac still received
//      --source 8 --target 8 and the warnings persisted. Kotlin, on the
//      other hand, reads `jvmTarget` at execution time, so its override did
//      stick — producing a Java=1.8 / Kotlin=17 mismatch that the Kotlin
//      Gradle Plugin then flagged as inconsistent.
//
// The supported fix is AGP's `androidComponents.finalizeDsl {}` hook. It
// fires after the plugin module's build.gradle has populated
// `compileOptions` but before AGP freezes the DSL, so the value we write
// here becomes authoritative and propagates cleanly into the JavaCompile
// task's --source/--target. No `-Xlint:-options` suppression needed.
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.api.variant.LibraryAndroidComponentsExtension>("androidComponents") {
            finalizeDsl { ext ->
                ext.compileOptions.sourceCompatibility = JavaVersion.VERSION_17
                ext.compileOptions.targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }
    plugins.withId("com.android.application") {
        extensions.configure<com.android.build.api.variant.ApplicationAndroidComponentsExtension>("androidComponents") {
            finalizeDsl { ext ->
                ext.compileOptions.sourceCompatibility = JavaVersion.VERSION_17
                ext.compileOptions.targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }
    // Kotlin reads jvmTarget at execution time from each KotlinCompile task,
    // so the typed compilerOptions DSL is the supported configuration point.
    plugins.withId("org.jetbrains.kotlin.android") {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
