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
// Force every Android plugin module to compile against API 36. Older plugins
// (e.g. file_picker 8.x) hardcode compileSdk 34, which the app's own setting
// can't override; that clashes with flutter_plugin_android_lifecycle, which
// requires its consumers to compile against 36+. Applied via reflection so it
// is agnostic to the AGP DSL surface (modern `compileSdk` Int property vs the
// legacy `compileSdkVersion(int)` method).
fun Project.forceCompileSdk36() {
    val androidExtension = extensions.findByName("android") ?: return
    runCatching {
        androidExtension.javaClass
            .getMethod("setCompileSdk", Integer::class.java)
            .invoke(androidExtension, 36)
    }.recoverCatching {
        androidExtension.javaClass
            .getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
            .invoke(androidExtension, 36)
    }
}

subprojects {
    project.evaluationDependsOn(":app")
    // evaluationDependsOn above can leave some subprojects already evaluated by
    // the time this runs; afterEvaluate() throws on those, so configure them
    // immediately and only defer the rest.
    if (state.executed) {
        forceCompileSdk36()
    } else {
        afterEvaluate { forceCompileSdk36() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
