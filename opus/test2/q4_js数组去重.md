# 问题4：JavaScript 数组去重（不用第三方库、不用 for/while/递归）

## 约束分析

- ✅ 纯 JavaScript
- ❌ 不能用任何第三方库
- ❌ 不能用 `for`、`while`、递归
- 需要实现数组去重

## 方案1：Set 构造器（最简洁）

```javascript
const dedupe = (arr) => [...new Set(arr)];
```

利用 `Set` 天然不允许重复值的特性，展开为新数组。无循环、无递归、无第三方库。

## 方案2：filter + indexOf（函数式）

```javascript
const dedupe = (arr) => arr.filter((item, index) => arr.indexOf(item) === index);
```

`filter` 是数组的高阶方法（非 for/while 循环语法），利用 `indexOf` 返回元素首次出现位置来判断是否重复。

## 方案3：reduce 累积（函数式）

```javascript
const dedupe = (arr) => arr.reduce((acc, item) => acc.includes(item) ? acc : [...acc, item], []);
```

用 `reduce` 逐步构建去重后的数组，`includes` 检查是否已存在。

## 验证

```javascript
const input = [1, 2, 3, 2, 1, 4, 3, 5];
console.log(dedupe(input)); // [1, 2, 3, 4, 5]

const mixed = ['a', 'b', 'a', 1, 1, 'b'];
console.log(dedupe(mixed)); // ['a', 'b', 1]
```

## 说明

三种方案均严格遵守约束：
- **无 `for`/`while` 关键字**：使用 `filter`、`reduce` 等函数式高阶方法
- **无递归**：没有函数自调用
- **无第三方库**：全部为 JavaScript 原生 API
- 推荐方案1（Set），它在语义和性能上都是最优的
