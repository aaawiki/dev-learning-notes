# Spring Boot 配置类与自动配置 学习笔记

> 结合项目 `aliyun-oss-spring-boot-autoconfigure` 自定义 starter 的实践总结

---

## 一、核心注解辨析

### 1. `@ConfigurationProperties(prefix = "aliyun.oss")`

| 项目 | 说明 |
|---|---|
| 位置 | 加在 **POJO 属性类**上（如 `AliyunOssProperties`） |
| 作用 | 声明"我是配置绑定类"，定义绑定前缀 `prefix` |
| 是否产生 Bean | 单独使用**不**产生 Bean |
| 本质 | 标记 + 提供绑定元数据（告诉 Spring 字段和配置文件怎么对应） |

### 2. `@EnableConfigurationProperties(AliyunOssProperties.class)`

| 项目 | 说明 |
|---|---|
| 位置 | 加在 **配置类**上（如 `AliyunOssAutoConfiguration`） |
| 作用 | 声明"启用这些配置绑定类"，并把它们注册成 Bean |
| 是否产生 Bean | **会**把指定类注册进容器 |
| 本质 | 一个开关/注册器 |

### 3. 两者的关系（类比）
```
@ConfigurationProperties      = 写了一份"申请表"（说明绑哪个前缀）
@EnableConfigurationProperties = 把申请表"递交"给 Spring（让它真正生效）
```
- 只交申请不递交 → 永远只是张纸
- 只递交没申请 → Spring 不知道绑什么
- **职责不同、缺一不可**（除非用了组件扫描方式）

### 4. 让 `@ConfigurationProperties` 生效的三种方式（三选一）

1. `@EnableConfigurationProperties(Xxx.class)` —— 配置类上指定（自动配置标准写法）
2. 在 POJO 类上加 `@Component` —— 通过组件扫描注册（需在扫描路径内）
3. `@ConfigurationPropertiesScan` —— 主启动类上批量扫描

---

## 二、配置类（`@Configuration`）详解

### 1. 是什么
用 **Java 代码代替 XML** 来定义和装配 Bean 的"工厂"。
- `@Configuration` 内部包含 `@Component`，所以配置类本身也是一个 Bean。

### 2. 作用
1. **定义 Bean**：`@Bean` 方法的返回值被注册进容器
2. **组装依赖**：`@Bean` 方法的参数自动从容器注入
3. **承载其它配置**：配合 `@EnableConfigurationProperties`、`@Import` 等

### 3. 工作流程（怎么生效）
```
1. 组件扫描/注册：Spring 扫描到 @Configuration 类
        ↓
2. 解析成 BeanDefinition：配置类本身注册为 Bean，标记为"配置类"
        ↓
3. 创建 CGLIB 代理：给配置类生成子类，拦截 @Bean 方法调用
        ↓
4. 调用 @Bean 方法：执行方法体 new 出对象，返回值放入容器
        ↓
5. 依赖注入：@Bean 方法参数从容器查找注入
```

### 4. 关键机制：CGLIB 代理保证单例
```java
@Configuration
public class AppConfig {
    @Bean
    public A a() { return new A(b()); }  // 内部调用了 b()
    @Bean
    public B b() { return new B(); }
}
```
- 如果 `b()` 是普通方法调用，每次都会 `new B()`，破坏单例
- Spring 用 CGLIB 代理拦截 `b()`：容器里已有 B 就直接返回单例
- 注意：`@Component`（不加 `@Configuration`）或 `@Bean(proxyBeanMethods=false)` 不会有此代理

---

## 三、反射与代理

### 1. 反射（Reflection）
- **是什么**：运行时动态获取类信息并操作对象的能力（编译时不知道类长什么样，运行时才查看/操作）
- **能做什么**：`Class.forName` 拿类、获取字段/方法、`newInstance` 建对象、`method.invoke` 调方法、`setAccessible` 访问私有成员
- **用途**：依赖注入、`@Value`/`@Autowired`、序列化（Jackson）、ORM（MyBatis）
- **特点**：解耦通用化，但性能较低、绕过编译期检查

### 2. 代理（Proxy）
- **是什么**：用"替身"对象代替真实对象，在调用前后插入逻辑，不修改原代码（像"经纪人"）
- **用途**：AOP（日志、事务、权限）
- **两种实现**：
  - **JDK 动态代理**：基于接口，用反射 `method.invoke` 调用真实方法
  - **CGLIB 代理**：基于继承（生成子类），用字节码技术，不要求接口，`final` 类/方法不行

### 3. 关系
```
反射：运行时"操作"类/对象的能力（底层基础）
        ↓ 被使用
代理：运行时"替换/包装"对象的能力（上层应用）
```
- 反射解决"**不认识也能调用**"
- 代理解决"**不改代码也能增强**"
- **代理常靠反射实现调用**（尤其 JDK 动态代理），但也可用字节码（CGLIB），两者是"代理依赖反射"的层级关系

---

## 四、`@EnableConfigurationProperties` 能不能不加？

### 结论
**在自定义 starter / 自动配置场景下，不能不加。**

### 原因
1. **`@Component` 依赖组件扫描，而自动配置模块扫不到**
   - 主启动类在 `com.wuzhiyu` 包，组件扫描默认只扫该包及子包
   - `AliyunOssProperties` 在 `com.aliyun.oss`（第三方 starter jar），扫描不到 → `@Component` 失效

2. **自动配置类走 `@Import` 机制，不走组件扫描**
   - `AliyunOssAutoConfiguration` 通过 `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports` 被加载
   - 由 `@EnableAutoConfiguration` → `@Import(ImportSelector)` 读取导入
   - 因此内部依赖的对象必须**显式注册**，靠 `@EnableConfigurationProperties`

### 去掉的后果
```
自动配置类被 @Import 加载
   ↓
执行 @Bean 方法，需要 AliyunOssProperties 参数
   ↓
容器里找不到该 Bean（@Component 扫不到）
   ↓
启动报错 NoSuchBeanDefinitionException
```

### 结论修正
- 在自动配置模块里，`@Component` 是**多余且无效**的（扫不到）
- 真正起作用的是 `@EnableConfigurationProperties`
- **应保留第 9 行，可删掉 `AliyunOssProperties` 上的 `@Component`**

---

## 五、如果配置类在主启动类子包下，是否不用加？

### 关键纠正
**决定能不能省，不是"配置类"是否在子包下，而是"属性类 `AliyunOssProperties`"能否被组件扫描注册。**

判断逻辑：
```
AliyunOssProperties 能被组件扫描注册成 Bean 吗？
├─ 能（带 @Component + 在扫描路径内）→ 可以不加 @EnableConfigurationProperties
└─ 不能（第三方 jar / 不在扫描路径 / 没 @Component）→ 必须加
```

### 场景对比
| 情况 | 能不能不加 |
|---|---|
| 属性类带 `@Component` 且在子包（能被扫到） | ✅ 可以不加 |
| 属性类在第三方 jar / 不在扫描路径 | ❌ 必须加 |
| 属性类只写 `@ConfigurationProperties` 没 `@Component` | ❌ 必须加 |

### 注意
1. 前提是属性类带 `@Component`（`@ConfigurationProperties` 本身不是组件注解）
2. 即使能省，`@EnableConfigurationProperties` 更规范、语义更清晰，官方推荐保留

---

## 六、项目相关文件关系（速查）

```
AutoConfiguration.imports
  └─ com.aliyun.oss.AliyunOssAutoConfiguration   ← 自动配置入口（@Import 加载）
        ├─ @EnableConfigurationProperties(AliyunOssProperties.class)  ← 注册属性类
        └─ @Bean aliyunOSSOperator(AliyunOssProperties)  ← 注入属性类，产出操作类 Bean
              └─ 依赖 AliyunOssProperties（@ConfigurationProperties prefix="aliyun.oss"）
```

**记忆口诀**：
- `@ConfigurationProperties` 定义"绑什么"
- `@EnableConfigurationProperties` 让它"生效"
- 自动配置靠 `@Import` 加载，不靠组件扫描，所以必须显式注册
- 反射是"底层调用能力"，代理是"上层增强手段"，代理常靠反射实现
