// HDFC SmartGateway / Juspay HyperSDK — client ID for asset pre-fetching
buildscript {
    extra["clientId"] = "hdfcmaster"
}

allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://maven.juspay.in/jp-build-packages/hyper-sdk/") }
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
