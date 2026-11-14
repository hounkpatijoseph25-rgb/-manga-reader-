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

// Certains plugins (ex. file_picker 8.x) déclarent encore un compileSdk obsolète
// (android-34), ce qui fait échouer `checkReleaseAarMetadata` face à nos dépendances
// AndroidX qui exigent android-36. On aligne donc tous les sous-projets Android sur
// le compileSdk de l'application.
subprojects {
    fun forceCompileSdk36() {
        val androidExt = extensions.findByName("android") ?: return
        val target = 36

        val alreadyOk = runCatching {
            val current = androidExt.javaClass.getMethod("getCompileSdk").invoke(androidExt)
            (current as? Int) == target
        }.getOrDefault(false)
        if (alreadyOk) return

        val applied = runCatching {
            (androidExt as groovy.lang.GroovyObject).setProperty("compileSdk", target)
        }.isSuccess

        if (!applied) {
            runCatching {
                androidExt.javaClass.methods
                    .firstOrNull { it.name == "setCompileSdk" && it.parameterTypes.size == 1 }
                    ?.invoke(androidExt, target)
            }
        }
        logger.lifecycle("compileSdk forcé à $target pour ${project.path}")
    }

    if (runCatching { afterEvaluate { forceCompileSdk36() } }.isFailure) {
        forceCompileSdk36()
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
