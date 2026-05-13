# 海运数据说明

## 文件清单

| 文件 | 格式 | 内容 |
|------|------|------|
| `od对需求_20260507_ych.csv` | CSV | OD 对周度需求量 (752 对) |
| `航线船期_20260507_ych.csv` | CSV | 3 条航线的标准化时刻表 |
| `AEU1.xlsx` | Excel | AEU1 航线详细航次表（含实际船名、ETB/ETD） |
| `AEU2.xlsx` | Excel | AEU2 航线详细航次表 |
| `AEU3.xls` | Excel | AEU3 航线详细航次表 |
| `AEU1.csv` | CSV | AEU1 转 CSV |
| `AEU2.csv` | CSV | AEU2 转 CSV |
| `AEU3.csv` | CSV | AEU3 转 CSV |

---

## OD 需求 (`od对需求_20260507_ych.csv`)

字段: `Origin, Destination, FFEPerWeek, Revenue_1, TransitTime`

- **Origin** — 始发港代码（如 CNSHA = 上海）
- **Destination** — 目的港代码（如 USLAX = 洛杉矶）
- **FFEPerWeek** — 周度需求（40 英尺标箱/周）
- **Revenue_1** — 单箱收入（美元/FFE）
- **TransitTime** — 运输时间（天）

### 大流量 OD 示例

| 始发 | 目的 | FFE/周 | 收入 | 运输天数 |
|------|------|--------|------|---------|
| CNSHA | USLAX | 1206 | 1610 | 17 |
| CNYTN | USLAX | 1865 | 1620 | 20 |
| CNSHA | NLRTM | 1052 | 2960 | 34 |
| CNSHA | DEBRV | 1860 | 3070 | 36 |
| NLRTM | HKHKG | 769 | 880 | 30 |
| CNYTN | NLRTM | 1347 | 2840 | 30 |

涉及港口约 50+ 个，覆盖亚洲、欧洲、北美、南美、非洲、大洋洲。

---

## 航线船期 (`航线船期_20260507_ych.csv`)

字段: `RouteID, PortOrder, Port, ETA_day, ETD_day`

3 条亚欧航线：

### AEU1 — 亚欧快航一线

方向: Eastbound（中国→欧洲→回程）

| 序 | 港码 | 港口 | 到港天 | 离港天 |
|----|------|------|--------|--------|
| 1 | CNTAO | 青岛 | 0 | 1 |
| 2 | CNSHA | 上海 | 3 | 4 |
| 3 | CNNGB | 宁波 | 5 | 6 |
| 4 | CNXMN | 厦门 | 8 | 9 |
| 5 | CNYTN | 盐田 | 10 | 11 |
| 6 | SGSIN | 新加坡 | 14 | 15 |
| 7 | GBFXT | 费利克斯托 | 45 | 46 |
| 8 | BEZEE | 泽布吕赫 | 48 | 49 |
| 9 | PLGDY | 格但斯克 | 52 | 53 |
| 10 | DEWVN | 威廉港 | 58 | 59 |
| 11 | SGSIN | 新加坡(回) | 95 | 96 |
| 12 | CNYTN | 盐田(回) | 100 | 101 |
| 13 | CNTAO | 青岛(回) | 105 | — |

总航次 ~105 天。Excel 中有 60 余条具体航次记录（周 51+）。

### AEU2 — 亚欧快航二线

方向: Eastbound（中国→欧洲→回程）

| 序 | 港码 | 港口 | 到港天 | 离港天 |
|----|------|------|--------|--------|
| 1 | CNNGB | 宁波 | 0 | 1 |
| 2 | CNSHA | 上海 | 3 | 4 |
| 3 | CNYTN | 盐田 | 6 | 7 |
| 4 | SGSIN | 新加坡 | 11 | 12 |
| 5 | MAPTM | 丹吉尔 | 36 | 37 |
| 6 | FRDKK | 敦刻尔克 | 41 | 42 |
| 7 | GBSOU | 南安普顿 | 44 | 45 |
| 8 | FRLEH | 勒阿弗尔 | 55 | 56 |
| 9 | MYPKG | 巴生港(回) | 95 | 96 |
| 10 | CNNGB | 宁波(回) | 105 | — |

总航次 ~105 天。Excel 中有 150+ 条航次记录。

### AEU3 — 亚欧快航三线

方向: Eastbound（华北→欧洲→回程）

| 序 | 港码 | 港口 | 到港天 | 离港天 |
|----|------|------|--------|--------|
| 1 | CNTXG | 天津 | 0 | 1 |
| 2 | CNDLC | 大连 | 3 | 4 |
| 3 | CNTAO | 青岛 | 5 | 6 |
| 4 | CNSHA | 上海 | 8 | 9 |
| 5 | CNNGB | 宁波 | 10 | 11 |
| 6 | SGSIN | 新加坡 | 16 | 17 |
| 7 | NLRTM | 鹿特丹 | 46 | 47 |
| 8 | DEHAM | 汉堡 | 50 | 51 |
| 9 | BEANR | 安特卫普 | 54 | 55 |
| 10 | CNSHA | 上海(回) | 95 | 96 |
| 11 | CNTXG | 天津(回) | 98 | — |

总航次 ~98 天。Excel 中有 60+ 条航次记录（含具体船名 COSCO SHIPPING CAPRICORN 等）。

---

## Excel 航次表结构

三个 Excel 文件结构类似，包含:
- **航线介绍行**: 航线名称、挂靠港说明
- **表头**: week, VESSEL NAME, VSL OPR, VSL CODE, VOYAGE NO.
- **港口列**: 每个港口两列（ETB = 预计靠泊, ETD = 预计离泊）
- **数据行**: 每周一班，含具体船名和实际/计划 ETB/ETD 日期

### 涉及的船公司

OOCL（东方海外）、CMA CGM（达飞）、COSCO SHIPPING（中远海运）

### 港口代码映射

| 代码 | 港口 |
|------|------|
| CNSHA | 上海 |
| CNTAO | 青岛 |
| CNYTN | 盐田 |
| CNNGB | 宁波 |
| CNXMN | 厦门 |
| CNTXG | 天津 |
| CNDLC | 大连 |
| SGSIN | 新加坡 |
| NLRTM | 鹿特丹 |
| DEHAM | 汉堡 |
| BEANR | 安特卫普 |
| GBFXT | 费利克斯托 |
| BEZEE | 泽布吕赫 |
| MAPTM | 丹吉尔 |
| MYPKG | 巴生港 |
| HKHKG | 香港 |
| USLAX | 洛杉矶 |
| USCHS | 查尔斯顿 |
| USEWR | 伊丽莎白 |
| ... | ... |

更多港口代码参考 OD 数据中的 Origin/Destination 列。
