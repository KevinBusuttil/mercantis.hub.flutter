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

// Force every Android plugin module to compile against API 36. Older plugins
// (e.g. file_picker 8.x) hardcode compileSdk 34, which the app's own setting
// can't override; that clashes with flutter_plugin_android_lifecycle, which
// requires its consumers to compile against 36+. Done via reflection so it is
// agnostic to the AGP DSL surface (modern `compileSdk` Int property vs the
// legacy `compileSdkVersion(int)` method).
subprojects {
    afterEvaluate {
        val androidExtension = extensions.findByName("android") ?: return@afterEvaluate
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
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
