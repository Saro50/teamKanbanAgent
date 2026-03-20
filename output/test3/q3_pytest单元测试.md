# 问题3：pytest 单元测试

> 每个函数至少覆盖：正常路径、边界条件、异常路径各一个用例。

```python
import pytest


# ========== 被测函数 ==========

def merge_dicts(*dicts, override=True):
    result = {}
    for d in dicts:
        for k, v in d.items():
            if override or k not in result:
                result[k] = v
    return result


def get_user(users, user_id):
    for user in users:
        if user['id'] == user_id:
            return user
    return None


def safe_divide(a, b):
    try:
        return a / b
    except ZeroDivisionError:
        return 0
    except TypeError as e:
        print(f'Type error: {e}')
        return None


# ========== merge_dicts 测试 ==========

class TestMergeDicts:
    def test_normal_merge_two_dicts(self):
        """正常路径：合并两个不重叠的字典"""
        result = merge_dicts({'a': 1}, {'b': 2})
        assert result == {'a': 1, 'b': 2}

    def test_override_true_last_wins(self):
        """正常路径：override=True 时后者覆盖前者"""
        result = merge_dicts({'a': 1}, {'a': 2}, override=True)
        assert result == {'a': 2}

    def test_override_false_first_wins(self):
        """正常路径：override=False 时保留先出现的值"""
        result = merge_dicts({'a': 1}, {'a': 2}, override=False)
        assert result == {'a': 1}

    def test_boundary_empty_dicts(self):
        """边界条件：所有输入都是空字典"""
        result = merge_dicts({}, {}, {})
        assert result == {}

    def test_boundary_no_arguments(self):
        """边界条件：不传任何字典"""
        result = merge_dicts()
        assert result == {}

    def test_boundary_single_dict(self):
        """边界条件：只传一个字典"""
        result = merge_dicts({'x': 10})
        assert result == {'x': 10}

    def test_exception_non_dict_input(self):
        """异常路径：传入非字典类型"""
        with pytest.raises(AttributeError):
            merge_dicts([1, 2, 3])


# ========== get_user 测试 ==========

class TestGetUser:
    @pytest.fixture
    def users(self):
        return [
            {'id': 1, 'name': 'Alice'},
            {'id': 2, 'name': 'Bob'},
            {'id': 3, 'name': 'Charlie'},
        ]

    def test_normal_find_existing_user(self, users):
        """正常路径：找到存在的用户"""
        result = get_user(users, 2)
        assert result == {'id': 2, 'name': 'Bob'}

    def test_normal_find_first_user(self, users):
        """正常路径：找到列表中第一个用户"""
        result = get_user(users, 1)
        assert result == {'id': 1, 'name': 'Alice'}

    def test_normal_find_last_user(self, users):
        """正常路径：找到列表中最后一个用户（验证不会提前返回 None）"""
        result = get_user(users, 3)
        assert result == {'id': 3, 'name': 'Charlie'}

    def test_boundary_user_not_found(self, users):
        """边界条件：用户 ID 不存在"""
        result = get_user(users, 999)
        assert result is None

    def test_boundary_empty_list(self):
        """边界条件：用户列表为空"""
        result = get_user([], 1)
        assert result is None

    def test_exception_invalid_user_format(self):
        """异常路径：用户对象缺少 'id' 键"""
        with pytest.raises(KeyError):
            get_user([{'name': 'NoId'}], 1)


# ========== safe_divide 测试 ==========

class TestSafeDivide:
    def test_normal_integer_division(self):
        """正常路径：整数除法"""
        assert safe_divide(10, 3) == pytest.approx(3.3333, rel=1e-3)

    def test_normal_float_division(self):
        """正常路径：浮点数除法"""
        assert safe_divide(7.5, 2.5) == 3.0

    def test_boundary_zero_divided_by_nonzero(self):
        """边界条件：0 除以非零数"""
        assert safe_divide(0, 5) == 0.0

    def test_boundary_divide_by_zero(self):
        """边界条件（异常路径）：除以零返回 0"""
        assert safe_divide(10, 0) == 0

    def test_boundary_negative_numbers(self):
        """边界条件：负数除法"""
        assert safe_divide(-10, 2) == -5.0

    def test_exception_type_error_string(self):
        """异常路径：传入字符串类型"""
        result = safe_divide("a", 2)
        assert result is None

    def test_exception_type_error_none(self):
        """异常路径：传入 None"""
        result = safe_divide(None, 2)
        assert result is None
```

## 覆盖矩阵

| 函数 | 正常路径 | 边界条件 | 异常路径 |
|------|----------|----------|----------|
| `merge_dicts` | 合并不重叠字典、override=True/False | 空字典、无参数、单字典 | 传入非字典类型 |
| `get_user` | 找到第1/2/3个用户 | ID 不存在、空列表 | 用户对象缺少 id 键 |
| `safe_divide` | 整数除法、浮点除法 | 0÷n、负数、÷0 | 字符串类型、None 类型 |
