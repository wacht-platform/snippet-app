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

// Universal compileSdk floor: some plugins (e.g. file_picker) pin a lower
// compileSdk than newer transitive deps require, which fails AAR metadata
// checks. Force every Android module (app + all plugins) up to this SDK.
// Reflection avoids needing the Android Gradle Plugin types on the root classpath.
val universalCompileSdk = 37
subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    // Registered before evaluationDependsOn (below) forces evaluation, so it's
    // always valid to add this afterEvaluate hook.
    afterEvaluate {
        val androidExt = project.extensions.findByName("android")
        if (androidExt != null) {
            runCatching {
                androidExt.javaClass
                    .getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                    .invoke(androidExt, universalCompileSdk)
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
