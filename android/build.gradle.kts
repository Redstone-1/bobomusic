allprojects {
    // Flutter 插件工程自带的 buildscript{} 只声明 google()/mavenCentral()，仓库按顺序命中，
    // 本机直连 Maven Central 会先超时；镜像必须排在这些工程求值前加入。
    buildscript {
        repositories {
            maven("https://maven.aliyun.com/repository/google")
            maven("https://maven.aliyun.com/repository/central")
        }
    }
    repositories {
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/central")
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
