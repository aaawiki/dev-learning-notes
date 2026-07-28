# 笔记标题：Java 编译报错"找不到符号"——Lombok 注解未生效的排查

> 日期：2026-07-28
> 标签：`Java` `Lombok` `IntelliJ-IDEA` `Maven` `编译报错` `黑马外卖`
> 类型：日志笔记（问题排查）

---

## 问题描述

在 **黑马 sky-takeout** 项目 day01 后端初始工程中，编译 `EmployeeController` 时报一系列「找不到符号」错误，全部指向 Lombok 本应自动生成的方法：

```
EmployeeController.java:48:54
java: 找不到符号
  符号:   方法 getId()
  位置: 类型为com.sky.entity.Employee的变量 employee

EmployeeController.java:54:58
java: 找不到符号
  符号:   方法 builder()
  位置: 类 com.sky.vo.EmployeeLoginVO

EmployeeController.java:55:29 ~ 57:31
java: 找不到符号
  符号:   方法 getId() / getUsername() / getName()
  位置: 类型为com.sky.entity.Employee的变量 employee
```

涉及的实体类 `Employee`、VO 类 `EmployeeLoginVO` 上都已正确加了 `@Data`、`@Builder`、`@NoArgsConstructor`、`@AllArgsConstructor` 注解，Maven 里也声明了 Lombok 依赖——也就是说 **代码本身没问题，是 Lombok 没有在编译期生效**。

---

## 解决方法

### 方案一：IDE 开启 Lombok 注解处理器（最常见原因）

1. **安装 Lombok 插件**：`File` → `Settings` → `Plugins` → 搜索 **Lombok** → 安装并重启 IDE
2. **开启注解处理器**：`File` → `Settings` → `Build, Execution, Deployment` → `Compiler` → `Annotation Processors` → ✅ 勾选 **Enable annotation processing**
3. **重新编译**：`Build` → `Rebuild Project`

> 较新版本 IDEA（2020.3+）Lombok 插件已内置，只需确认步骤 2 已勾选即可。

### 方案二：Lombok 版本过低，不兼容当前 JDK（已开注解处理器仍报错时）

项目用的 **Lombok 1.18.20（2021 年发布）最高只支持到 JDK 16**。若本机 JDK 是 **17 或更高**，注解处理器会静默失败——不报错也不生成代码，表现和没开注解处理器一样。

**统一升级到 `1.18.30`**（支持 JDK 17/18/19/20/21）：

父 `pom.xml` 的 `<properties>`：
```xml
<lombok>1.18.30</lombok>
```

`sky-pojo/pom.xml` 与 `sky-server/pom.xml`：
```xml
<dependency>
    <groupId>org.projectlombok</groupId>
    <artifactId>lombok</artifactId>
    <version>1.18.30</version>
</dependency>
```

改完后：
1. IDEA 右侧 Maven 面板点击 🔄 **Reload All Maven Projects**
2. `Build` → `Rebuild Project`

### 仍不行的兜底排查

| 排查项 | 操作 |
|--------|------|
| ① 确认 JDK 版本 | `File` → `Project Structure` → `Project` 查看 SDK 版本 |
| ② 清除 Maven 缓存 | `cmd` 中执行：`cd /d D:\develop\黑马\sky-takeout\资料\day01\后端初始工程\sky-take-out && mvn clean install -DskipTests` |
| ③ 删除 IDEA 缓存 | `File` → `Invalidate Caches` → 全部勾选 → `Invalidate and Restart` |

---

## 原理分析

**为什么加了 `@Data` 还找不到 `getId()`？**

Lombok 不是运行时库，而是一个**编译期注解处理器（annotation processor）**。它在 `javac` 编译阶段扫描 `@Data` 等注解，动态生成 getter/setter/`equals`/`hashCode`/`builder()` 等代码，再交给编译器。如果注解处理器没跑起来，这些代码根本不存在，编译器自然报「找不到符号」。

**为什么 Lombok 版本会和 JDK 版本强相关？**

Lombok 通过操作 Java 编译器的内部 API 来注入代码，这些内部 API 随 JDK 大版本变化。**Lombok 1.18.20 只适配到 JDK 16**，对 JDK 17+ 的新内部 API 不兼容，表现为注解处理器「静默失效」——这是最容易踩、也最隐蔽的一种情况，因为控制台不一定有明显报错。

**两个触发条件的区别**
- 注解处理器没开 → 所有 Lombok 注解都不生效
- 注解处理器开了但 Lombok 版本太低 → 高版本 JDK 下同样不生效，且更难察觉

---

## 感悟

- **先看报错性质，再判断方向**：一连串 `找不到符号` 且全是 getter/builder 这类「本该自动生成」的方法，基本可以直接锁定 Lombok 没生效，不用去翻实体类代码。
- **「已配置但不生效」要往版本兼容性想**：很多人把注解处理器开了就以为万事大吉，忽略了 Lombok 版本与 JDK 版本的硬约束。这是依赖管理里很典型的一类坑。
- **静默失败比报错更危险**：Lombok 版本不匹配时不会大声报错，只是「什么都没生成」，排查时容易在错误的方向上浪费时间。养成「先确认工具链版本矩阵」的习惯能省很多事。
- **排查顺序**：IDE 配置（插件 + 注解处理器）→ 依赖版本（Lombok ↔ JDK）→ 缓存清理（Maven + IDEA）。由浅入深，不要一上来就 invalidate caches。

---

*参考项目：黑马 sky-takeout day01 后端初始工程（sky-server / sky-pojo）。*
