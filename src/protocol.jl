# ============================================================
# protocol.jl — AnySim 仿真协议层
#
# 抽象 Julia AnySim 引擎 ↔ 前端（Web/CLI/文件）通信协议。
# 与领域无关，所有求解器都能用。
#
# 架构:
#   SimState / EngineCommand    — 结构化数据（与领域无关）
#   serialize_state()           — 通用状态序列化
#   deserialize_command()       — 通用命令反序列化
#   AbstractSimTransport        — 传输层接口（可拔插）
#
# 用法:
#   ctx = init_devs_context(model)
#   state = serialize_state(ctx)
#   json_str = JSON3.write(state)   # 交给具体 JSON 库
# ============================================================

# ============================================================
# 1. 结构化数据类型（与领域无关）
# ============================================================

"""
    SimState

泛化仿真状态快照，与具体的求解器类型无关。
所有求解器（DEVS/DESolver/ODE）都序列化为这种形式。

字段说明:
- `type` — 状态类型标签，如 "sim_state", "sim_result", "sim_error"
- `time` — 当前仿真时间
- `entities` — entity 名称 → entity 状态 Dict 的映射
- `step` — 当前步数（可选）
- `metadata` — 额外元数据（如求解器名称、协议版本）
"""
struct SimState
    type::String
    time::Float64
    entities::Dict{String, Dict{String, Any}}
    step::Int
    metadata::Dict{String, Any}
end

# 便捷构造函数
SimState(time::Float64, entities::Dict{String, Dict{String, Any}}) =
    SimState("sim_state", time, entities, 0, Dict{String, Any}())

function make_error_state(diag::Diagnostic; time=0.0, step=0, extra_metadata=Dict{String,Any}())
    metadata = merge(
        Dict{String, Any}(
            "diagnostic" => diagnostic_to_dict(diag),
        ),
        extra_metadata,
    )
    return SimState("sim_error", Float64(time), Dict{String, Dict{String, Any}}(), step, metadata)
end

diagnostic_payload(diag::Diagnostic; time=0.0, step=0, extra_metadata=Dict{String,Any}()) =
    _simstate_to_dict(make_error_state(diag; time=time, step=step, extra_metadata=extra_metadata))

diagnostic_payload(err::DiagnosticError; time=0.0, step=0, extra_metadata=Dict{String,Any}()) =
    diagnostic_payload(err.diagnostic; time=time, step=step, extra_metadata=extra_metadata)

function exception_payload(err::Exception; time=0.0, step=0,
                           extra_metadata=Dict{String,Any}(),
                           phase="simulation_runtime",
                           human_message="未处理异常",
                           entity=Dict{String, String}())
    if err isa DiagnosticError
        return diagnostic_payload(err; time=time, step=step, extra_metadata=extra_metadata)
    end
    diag = diagnostic_from_exception(
        err;
        phase=phase,
        human_message=human_message,
        human_summary=string(err),
        entity=entity,
    )
    return diagnostic_payload(diag; time=time, step=step, extra_metadata=extra_metadata)
end

"""
    EngineCommand

前端发给仿真引擎的命令。
与求解器类型无关，所有求解器都能处理。

命令类型:
- :start     → 启动仿真 {params, tspan, solver}
- :stop      → 停止仿真 {}
- :pause     → 暂停仿真 {}
- :resume    → 恢复仿真 {}
- :set_param → 设置参数 {entity, param, value}
- :set_speed → 设置仿真速度 {speed}
- :step      → 单步执行 {}
- :query     → 查询状态 {path}
"""
struct EngineCommand
    type::Symbol       # 命令类型
    params::Dict{String, Any}  # 命令参数
    id::String         # 命令 ID（用于响应跟踪）
end

EngineCommand(type::Symbol, params::Dict{String, Any}) =
    EngineCommand(type, params, "")

# ============================================================
# 2. 协议抽象接口
#
# Julia 通过多重分派实现协议接口，不需要显式接口关键字。
# 遵循 Duck Typing: 实现以下方法的类型即遵从此协议。
#
# 必需方法:
#   serialize_state(transport, sim_state) → Dict{String, Any}
#   deserialize_command(transport, json_dict) → EngineCommand
#   broadcast_state(transport, state_dict)
#   send_command(transport, command)
# ============================================================

"""
    AbstractSimTransport

仿真传输层的抽象基类。
子类需实现:
- `serialize_state(t, state)`   # SimState → Dict{String, Any}
- `deserialize_command(t, d)`   # Dict{String, Any} → EngineCommand
- `broadcast_state(t, d)`       # 发送状态到前端
- `send_command(t, c)`          # 发送命令到后端
"""
abstract type AbstractSimTransport end

# 默认方法（由子类覆盖）
serialize_state(t::AbstractSimTransport, state::SimState) = _simstate_to_dict(state)
deserialize_command(t::AbstractSimTransport, data::Dict{String,Any}) = _dict_to_command(data)

# 传输方法（子类必须实现）
function broadcast_state end
function send_command end

# ============================================================
# 3. 通用状态序列化（SimState ↔ Dict{String, Any}）
# ============================================================

"""
    _simstate_to_dict(state::SimState) -> Dict{String, Any}

将 SimState 转换为纯 Dict{String, Any}，可直接 JSON 序列化。
"""
function _simstate_to_dict(state::SimState)
    return Dict{String, Any}(
        "type" => state.type,
        "time" => state.time,
        "entities" => state.entities,
        "step" => state.step,
        "metadata" => state.metadata,
    )
end

"""
    _dict_to_command(data::Dict{String, Any}) -> EngineCommand

将前端发来的 Dict（已从 JSON 解析）转为 EngineCommand。
"""
function _dict_to_command(data::Dict{String,Any})
    raw_type = get(data, "type", get(data, "cmd", "query"))
    cmd_type = Symbol(raw_type)
    raw_params = get(data, "params", get(data, "payload", Dict{String,Any}()))
    params = raw_params isa Dict{String,Any} ? raw_params : Dict{String,Any}(pairs(raw_params))
    cmd_id = get(data, "id", "")
    return EngineCommand(cmd_type, params, cmd_id)
end

# ============================================================
# 4. 求解器状态 → SimState 转换器
#
# 将各求解器的内部状态格式统一转换为 SimState。
# 所有转换器输出相同结构，前端无需区分求解器类型。
# ============================================================

"""
    make_sim_state(time::Float64,
                   states::Dict{Symbol, Dict{Symbol, Any}},
                   params::Vector{Parameter};
                   step=0, metadata=Dict()) -> SimState

=== 核心转换函数 ===

将 "entity_name → {var_name → value}" 格式的状态字典转换为 SimState。

过滤规则:
- `_` 前缀字段 → 视为运行时内部态，默认不外露
- Number 类型 → 直接保留
- Symbol 类型 → 转为 String
- Bool 类型 → 转为 Bool
- 其他类型（Vector, Struct 等）→ 跳过（内部数据结构不外露）
"""
function make_sim_state(time::Float64,
                        states::Dict{Symbol, Dict{Symbol, Any}},
                        all_entities::Vector{EntityDef};
                        step=0, extra_metadata=Dict{String,Any}())
    entities = Dict{String, Dict{String, Any}}()

    for e in all_entities
        ent_name = string(e.name)
        ent_data = Dict{String, Any}()

        if haskey(states, e.name)
            raw_state = states[e.name]
            for (k, v) in raw_state
                # 跳过内部变量（以 _ 开头的系统变量）
                k_str = string(k)
                startswith(k_str, "_") && continue

                if v isa Number
                    ent_data[k_str] = Float64(v)
                elseif v isa Symbol
                    ent_data[k_str] = string(v)
                elseif v isa Bool
                    ent_data[k_str] = v
                elseif v isa String
                    ent_data[k_str] = v
                end
                # 其他类型（Vector, Struct, DEVSMessage[] 等）跳过
            end
        end

        # 添加参数元数据（类型、单位）
        param_meta = Dict{String, Any}()
        for p in e.parameters
            pname = string(p.name)
            startswith(pname, "_") && continue
            meta = Dict{String, Any}("type" => string(p.ptype))
            if p.unit !== nothing
                meta["unit"] = p.unit
            end
            if p.default !== nothing
                if p.default isa Number
                    meta["default"] = p.default
                elseif p.default isa Symbol
                    meta["default"] = string(p.default)
                end
            end
            param_meta[pname] = meta
        end
        if !isempty(param_meta)
            ent_data["meta"] = Dict{String, Any}("params" => param_meta)
        end

        if !isempty(ent_data)
            entities[ent_name] = ent_data
        end
    end

    return SimState("sim_state", time, entities, step, extra_metadata)
end

# SimResult 的重载版本（用于仿真结束后的结果快照）
#
# 注意: DEVSContext 的 make_sim_state 重载定义在 DEVS.jl 中，
# 因为 protocol.jl 在加载时 DEVS 尚未被 include。
function make_sim_state(result::SimResult; step=0)
    entities = Dict{String, Dict{String, Any}}()
    n_t = length(result.t)
    last_idx = n_t

    # 从 SimResult.u 提取数值型状态
    for (i, sname) in enumerate(result.states)
        parts = split(string(sname), "_"; limit=2)
        if length(parts) == 2
            ent_name = parts[1]
            var_name = parts[2]
            ent = get!(entities, ent_name, Dict{String, Any}())
            ent[var_name] = result.u[i, last_idx]
        end
    end

    # 从 raw 提取非数值型状态
    for (sname, vals) in result.raw
        parts = split(string(sname), "_"; limit=2)
        if length(parts) == 2
            ent_name = parts[1]
            var_name = parts[2]
            if last_idx <= length(vals)
                v = vals[last_idx]
                ent = get!(entities, ent_name, Dict{String, Any}())
                if v isa Number
                    ent[var_name] = Float64(v)
                elseif v isa Symbol
                    ent[var_name] = string(v)
                elseif v isa Bool
                    ent[var_name] = v
                elseif v isa String
                    ent[var_name] = v
                end
            end
        end
    end

    t_end = isempty(result.t) ? 0.0 : result.t[end]
    return SimState(t_end, entities, step, result.params)
end

# ============================================================
# 5. 历史状态序列化（用于回放/分析）
# ============================================================

"""
    serialize_history(times::Vector{Float64},
                      records::Vector{Dict{Symbol, Dict{Symbol, Any}}},
                      all_entities::Vector{EntityDef}) -> Vector{SimState}

将仿真历史记录转换为 SimState 序列，用于:
- 仿真回放（前端接收完整轨迹）
- 导出为 JSON 文件
- 跨会话分析
"""
function serialize_history(times::Vector{Float64},
                           records::Vector{Dict{Symbol,Dict{Symbol,Any}}},
                           all_entities::Vector{EntityDef})
    n = min(length(times), length(records))
    states = Vector{SimState}(undef, n)
    for i in 1:n
        states[i] = make_sim_state(times[i], records[i], all_entities; step=i-1)
    end
    return states
end

function _make_sim_state_at(result::SimResult, idx::Int)
    entities = Dict{String, Dict{String, Any}}()

    for (state_i, sname) in enumerate(result.states)
        parts = split(string(sname), "_"; limit=2)
        if length(parts) == 2
            ent_name = parts[1]
            var_name = parts[2]
            ent = get!(entities, ent_name, Dict{String, Any}())
            ent[var_name] = result.u[state_i, idx]
        end
    end

    for (sname, values) in result.raw
        parts = split(string(sname), "_"; limit=2)
        if length(parts) == 2 && idx <= length(values)
            ent_name = parts[1]
            var_name = parts[2]
            ent = get!(entities, ent_name, Dict{String, Any}())
            val = values[idx]
            if val isa Symbol
                ent[var_name] = string(val)
            elseif val isa String || val isa Bool || val isa Number
                ent[var_name] = val
            end
        end
    end

    return SimState("sim_result", result.t[idx], entities, idx, Dict{String, Any}())
end

function serialize_history(result::SimResult)
    n = length(result)
    states = Vector{SimState}(undef, n)
    for i in 1:n
        states[i] = _make_sim_state_at(result, i)
    end
    return states
end

# ============================================================
# 6. 变更检测（增量更新用，Phase 4 完整实现）
# ============================================================

"""
    compute_diff(prev::Dict{String, Dict{String, Any}},
                 curr::Dict{String, Dict{String, Any}}) -> Dict{String, Dict{String, Any}}

计算两个 entity 状态字典之间的差异。
只返回发生变化的字段。用于增量更新以减少前端传输量。
"""
function compute_diff(prev::Dict{String, Dict{String, Any}},
                      curr::Dict{String, Dict{String, Any}})
    diff = Dict{String, Dict{String, Any}}()

    # 检查新增或变化的 entity
    for (ent_name, curr_data) in curr
        prev_data = get(prev, ent_name, nothing)
        if prev_data === nothing
            # 新增 entity
            diff[ent_name] = curr_data
        else
            ent_diff = Dict{String, Any}()
            for (k, v) in curr_data
                if !haskey(prev_data, k) || prev_data[k] != v
                    ent_diff[k] = v
                end
            end
            if !isempty(ent_diff)
                diff[ent_name] = ent_diff
            end
        end
    end

    # 检查删除的 entity（标记为 null）
    for (ent_name, _) in prev
        if !haskey(curr, ent_name)
            diff[ent_name] = Dict{String, Any}("__deleted__" => true)
        end
    end

    return diff
end

# ============================================================
# 7. 文件传输（用于批量仿真导出）
# ============================================================

"""
    FileTransport — 文件传输实现

将仿真状态写入 JSON 文件，用于:
- 批量仿真后分析
- 离线回放
- 测试数据生成
"""
struct FileTransport <: AbstractSimTransport
    output_dir::String
    format::Symbol  # :json, :jsonlines
end

FileTransport(; output_dir=".", format=:jsonlines) =
    FileTransport(output_dir, format)

function broadcast_state(t::FileTransport, state::SimState)
    dict = serialize_state(t, state)
    return dict  # 返回 Dict，由调用方决定何时写入文件
end

# SimState 的序列化扩展（添加协议元数据）
function serialize_state(t::FileTransport, state::SimState)
    d = _simstate_to_dict(state)
    d["protocol"] = "anysim-v1"
    return d
end

"""
    write_states_to_file(t::FileTransport, states::Vector{SimState})

将一组 SimState 写入文件。
JSONLines 格式（每行一个 JSON 对象）适合流式处理。
"""
function write_states_to_file(t::FileTransport, states::Vector{SimState})
    ts = replace(string(round(time(), digits=0)), "." => "_")
    filename = joinpath(t.output_dir, "anysim_export_$(ts)")

    if t.format == :jsonlines
        filename *= ".jsonl"
        open(filename, "w") do io
            for state in states
                d = serialize_state(t, state)
                println(io, _dict_to_json(d))
            end
        end
    else
        filename *= ".json"
        dicts = [serialize_state(t, s) for s in states]
        open(filename, "w") do io
            # 格式化输出（缩进）
            println(io, "[")
            for (i, d) in enumerate(dicts)
                write(io, "  ")
                println(io, _dict_to_json(d))
                if i < length(dicts)
                    println(io, ",")
                else
                    println(io)
                end
            end
            println(io, "]")
        end
    end

    return filename
end

# ============================================================
# 8. JSON 辅助（无外部依赖的简单序列化）
#
# 核心字典转 JSON 字符串。
# 主要用于 FileTransport 和调试输出。
# 正式 WebSocket 传输推荐使用 JSON3.jl 或 JSON.jl。
# ============================================================

function _dict_to_json(d::Dict{String,Any})
    parts = String[]
    for (k, v) in d
        push!(parts, "  $(json_escape(string(k))): $(json_val(v))")
    end
    return "{\n" * join(parts, ",\n") * "\n}"
end

function json_val(v::Any)
    if v === nothing
        return "null"
    elseif v isa Bool
        return string(v)
    elseif v isa Number
        return string(v)
    elseif v isa String
        return json_escape(v)
    elseif v isa Dict
        return json_object(v)
    elseif v isa Vector
        return json_array(v)
    else
        return json_escape(string(v))
    end
end

json_val(v::Dict{String,Any}) = json_object(v)
json_val(v::Vector) = json_array(v)

function json_object(d::Dict)
    pairs = String[]
    for (k, v) in d
        push!(pairs, "$(json_escape(string(k))): $(json_val(v))")
    end
    return "{" * join(pairs, ", ") * "}"
end

function json_array(a::Vector)
    vals = String[json_val(v) for v in a]
    return "[" * join(vals, ", ") * "]"
end

function json_escape(s::String)
    buf = IOBuffer()
    write(buf, '"')
    for c in s
        if c == '"'
            write(buf, "\\\"")
        elseif c == '\\'
            write(buf, "\\\\")
        elseif c == '\n'
            write(buf, "\\n")
        elseif c == '\r'
            write(buf, "\\r")
        elseif c == '\t'
            write(buf, "\\t")
        else
            write(buf, c)
        end
    end
    write(buf, '"')
    return String(take!(buf))
end

println("[Protocol] AnySim Simulation Protocol loaded. Version: v1")
