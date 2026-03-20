# 问题1：找出以下三个 Python 函数中的所有 bug（只列问题，不给修复代码）

## 函数1：`merge_dicts`

```python
def merge_dicts(*dicts, override=True):
    result = {}
    for d in dicts:
        for k, v in d:            # ← bug
            if override or k not in result:
                result[k] = v
    return result
```

**Bug：`for k, v in d` 应为 `for k, v in d.items()`**

- 对一个 `dict` 直接迭代（`for k, v in d`）实际上是在迭代字典的 **键**，而不是键值对。
- 如果键是长度为 2 的字符串或元组，Python 会将其解包为 `k, v`，产生错误但不报异常的静默逻辑错误。
- 如果键不是长度为 2 的可迭代对象，则会抛出 `ValueError: not enough values to unpack`。
- 正确做法是调用 `.items()` 方法来获取键值对。

---

## 函数2：`get_user`

```python
def get_user(users, user_id):
    for user in users:
        if user['id'] == user_id:
            return user
        return None               # ← bug
```

**Bug：`return None` 缩进错误，位于 `for` 循环体内部**

- `return None` 与 `if` 同级，意味着它在 `else` 分支的位置（隐式 else）。
- 效果：循环在**第一次迭代**后就会返回 —— 要么找到匹配返回 `user`，要么直接返回 `None`。
- 即使列表中有 100 个用户，也只会检查第一个。
- `return None` 应该与 `for` 同级（减少一层缩进），在循环结束后才执行。

---

## 函数3：`safe_divide`

```python
def safe_divide(a, b):
    try:
        return a / b
    except ZeroDivisionError:
        return 0
    except TypeError as e:
        print(f'Type error: {e}')  # ← bug
```

**Bug：`TypeError` 异常分支没有 `return` 语句**

- 当 `a` 或 `b` 是不可除的类型（如字符串）时，捕获 `TypeError` 后只是 `print` 了错误信息，函数隐式返回 `None`。
- 一个名为 `safe_divide` 的函数在异常时静默返回 `None`，调用方无法区分"正常结果为 None"和"发生了类型错误"，容易引发下游 bug。
- 应该在 `except TypeError` 分支中也有一个明确的 `return` 值（或重新抛出异常）。

---

## 汇总

| 函数 | Bug 类型 | 严重程度 |
|------|----------|----------|
| `merge_dicts` | 遗漏 `.items()` 调用 → 迭代字典键而非键值对 | 🔴 高（功能错误/运行时异常） |
| `get_user` | `return None` 缩进错误 → 只检查第一个元素 | 🔴 高（逻辑错误，静默失败） |
| `safe_divide` | `TypeError` 分支无返回值 → 隐式返回 `None` | 🟡 中（异常处理不完整） |
