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

// 旧插件 receive_sharing_intent:1.8.1 未声明任何 JVM 目标：
// Java 侧取 AGP 默认 11，Kotlin 侧（KGP 2.3.20）跟随运行 Gradle 的 JDK，
// 两边不一致触发 "Inconsistent JVM Target Compatibility" 直接失败。
// 这里把该模块的 Java 对齐到“当前运行 Gradle 的 JDK 版本”
//（JavaVersion.current，与 KGP 默认跟随策略一致），
// 无论本机 JDK 21 还是 CI 的 JDK 都自洽，不再写死。
// 只用 Gradle 核心 API，无 KGP 类型依赖。
// 注意必须用 projectsEvaluated：AGP 在自己的 afterEvaluate 里设默认值，
// 普通 afterEvaluate 会被它覆盖。若将来插件升级后自带 JVM 配置，此段可删除。
gradle.projectsEvaluated {
    val gradleJvm = JavaVersion.current().toString()
    findProject(":receive_sharing_intent")?.tasks?.withType<JavaCompile>()
        ?.configureEach {
            sourceCompatibility = gradleJvm
            targetCompatibility = gradleJvm
        }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
