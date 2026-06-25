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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    val injectNamespace = {
        if (plugins.hasPlugin("com.android.library")) {
            val android = extensions.findByName("android")
            if (android != null) {
                // Force compileSdk to at least 35 to satisfy dependency requirements
                try {
                    val setCompileSdk = android.javaClass.getMethod("setCompileSdk", Int::class.java)
                    setCompileSdk.invoke(android, 35)
                    logger.quiet("Forced compileSdk to 35 for subproject ${project.name}")
                } catch (e: Exception) {
                    try {
                        val compileSdkVersion = android.javaClass.getMethod("compileSdkVersion", Int::class.java)
                        compileSdkVersion.invoke(android, 35)
                        logger.quiet("Forced compileSdkVersion to 35 for subproject ${project.name}")
                    } catch (e2: Exception) {
                        // Ignore if reflection fails
                    }
                }

                try {
                    val getNamespace = android.javaClass.getMethod("getNamespace")
                    val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
                    if (getNamespace.invoke(android) == null) {
                        val packageName = "com.mindflow.${project.name.replace("-", "_").replace(".", "_")}"
                        setNamespace.invoke(android, packageName)
                        logger.quiet("Injected namespace $packageName into subproject ${project.name}")
                    }
                } catch (e: Exception) {
                    // Ignore if reflection fails
                }
            }
            
            try {
                val manifestFile = file("src/main/AndroidManifest.xml")
                if (manifestFile.exists()) {
                    var content = manifestFile.readText()
                    if (content.contains("package=\"")) {
                        val regex = """package\s*=\s*"[^"]*"""".toRegex()
                        content = content.replace(regex, "")
                        manifestFile.writeText(content)
                        logger.quiet("Stripped package attribute from ${project.name} AndroidManifest.xml")
                    }
                }
            } catch (e: Exception) {
                // Ignore if manifest edit fails
            }
        }
    }
    
    if (state.executed) {
        injectNamespace()
    } else {
        afterEvaluate {
            injectNamespace()
        }
    }
}
