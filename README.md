# 多轮自然语言 Agent 评估方案

本工具用于对比评估两个 Agent CLI 在相同问题序列下的表现差异。

核心设计目标：通过连续多轮对话（累积上下文）的方式驱动两个 Agent 回答同一批问题，自动采集输出结果并生成对比报告；配合预设的评分模板，由独立评估 Agent 按标准打分，输出结构化评估结论，辅助判断不同 Agent 的能力边界与适用场景。

---

## 使用

**1. 配置参与对比的 Agent 命令**

编辑 `src/cmd.conf`，每行一个 Agent：

```
kode -p            |
claude-internal -p |
```

**2. 准备测试批次**

在 `src/tests/` 新建 `batch_XX_name.csv`，写入测试题目；可选同名 `.template.md` 定义评分标准。

**3. 运行**

```bash
./auto-ask.sh -t src/tests/batch_01_basic.csv   # 指定批次
./auto-ask.sh --all                              # 全部批次
```

结果保存在 `results/` 目录，有模板时自动生成评估报告。

