# ============================================================
# shipping_models.jl — 海运 DEVS 原子/耦合模型
#
# 对应 Python 参考实现中的:
#   models/vessel.py → VesselSailing
#   models/port.py   → PortTerminal
#   models/demand.py → DemandGenerator
#   models/network.py → MultiVesselRoute, ShippingNetwork
#
# 使用 AnySim DEVS 框架 (EntityDef + @devs_atomic + @compose)
# ============================================================

# ============================================================
# 1. 行为代码定义（用 quote 创建 Expr，可被 compile_relation 编译）
#
# 行为代码中可用的变量:
#   - state: 状态字典（DEVS 函数参数）
#   - dt:    DESolver 的时间步长
#   - 所有 state 变量 (被 compile_relation 自动解包为局部变量)
#
# 可用的辅助函数:
#   hold_in(state, :phase, sigma), passivate(state), activate(state)
#   devs_send!(state, :port, value), devs_receive(state, :port)
# ============================================================

# ---- VesselSailing: ta 函数 ----
# 根据当前阶段计算 _sigma（时间推进）
# 支持扰动：sailing 时间可被 disturbance_factor 缩放
function _vessel_ta_body()
    quote
        if _phase == :sailing
            pc = route_data.port_calls[current_idx]
            if current_idx == 1
                # 首次出航：考虑 start_delay（支持多船错开发船）
                base_sigma = start_delay + pc.eta_day
            else
                # 后续航段：相对航行时间（eta_next - etd_prev）
                prev_pc = route_data.port_calls[current_idx - 1]
                prev_etd = prev_pc.etd_day === nothing ? pc.eta_day : prev_pc.etd_day
                base_sigma = max(pc.eta_day - prev_etd, 0.0)
            end
            # Apply disturbance: multiply sailing time by factor (1.0 = no disturbance)
            _sigma = base_sigma * disturbance_factor
        elseif _phase == :in_port
            pc = route_data.port_calls[current_idx]
            base_stay = pc.etd_day === nothing ? 0.0 : pc.etd_day - pc.eta_day
            # Port operations can also be disturbed
            _sigma = base_stay * port_disturbance_factor
        elseif _phase == :done
            _sigma = 0.0
        else
            _sigma = INFINITY
        end
    end
end

# ---- VesselSailing: lambdaf（输出函数）----
# 到港时输出 ARRIVAL 事件 + 卸货
# 离港时输出 DEPARTURE 事件
function _vessel_lambdaf_body()
    quote
        if _phase == :sailing
            pc = route_data.port_calls[current_idx]
            eta = start_delay + pc.eta_day
            # 判断是否回程
            is_ret = false
            for i in 1:(current_idx - 1)
                if route_data.port_calls[i].port_code == pc.port_code
                    is_ret = true
                    break
                end
            end
            # 发送到港事件
            push!(_outbox, DEVSMessage(:o_arrival, Main.Shipping.VesselEvent(
                vessel_name, route_data.route_id,
                pc.port_code, "ARRIVAL", eta, pc.port_order, is_ret
            )))
            # 卸下目的港为本港的货物
            for c in loaded_cargo
                if c.destination == pc.port_code
                    c.sim_time = eta
                    push!(_outbox, DEVSMessage(:o_cargo_discharge, c))
                end
            end
        elseif _phase == :in_port
            pc = route_data.port_calls[current_idx]
            if pc.etd_day !== nothing
                etd = start_delay + pc.etd_day
                is_ret = false
                for i in 1:(current_idx - 1)
                    if route_data.port_calls[i].port_code == pc.port_code
                        is_ret = true
                        break
                    end
                end
                push!(_outbox, DEVSMessage(:o_departure, Main.Shipping.VesselEvent(
                    vessel_name, route_data.route_id,
                    pc.port_code, "DEPARTURE", etd, pc.port_order, is_ret
                )))
            end
        end
    end
end

# ---- VesselSailing: deltint（内部转移）----
function _vessel_deltint_body()
    quote
        if _phase == :sailing
            # 刚到港：移除已卸货物
            pc = route_data.port_calls[current_idx]
            filtered = Main.Shipping.CargoBatch[]
            for c in loaded_cargo
                if c.destination != pc.port_code
                    push!(filtered, c)
                end
            end
            loaded_cargo = filtered
            _phase = :in_port
            _sigma = Float64(Main.Shipping.duration(pc))
        elseif _phase == :in_port
            # 离港：前进到下一港
            current_idx = current_idx + 1
            if current_idx > length(route_data.port_calls)
                _phase = :done
                _sigma = 0.0
            else
                prev_pc = route_data.port_calls[current_idx - 1]
                curr_pc = route_data.port_calls[current_idx]
                prev_etd = prev_pc.etd_day === nothing ? curr_pc.eta_day : prev_pc.etd_day
                sailing_time = max(curr_pc.eta_day - prev_etd, 0.0)
                _phase = :sailing
                _sigma = Float64(sailing_time)
            end
        elseif _phase == :done
            _phase = :passive
            _sigma = INFINITY
        end
    end
end

# ---- VesselSailing: deltext（外部转移）----
# 接收装船货物（只接收指定给本船的）
function _vessel_deltext_body()
    quote
        local e = dt
        # 检查是否有装船货物（遍历局部 _inbox）
        for msg in _inbox
            if msg.port == :i_cargo
                cargo = msg.value
                if cargo.assigned_vessel == vessel_name || cargo.assigned_vessel == ""
                    push!(loaded_cargo, cargo)
                end
            end
        end
        _sigma = _sigma - Float64(e)
    end
end

# ---- PortTerminal: ta 函数 ----
function _port_ta_body()
    quote
        if _phase == :active
            _sigma = 0.0
        else
            _sigma = INFINITY
        end
    end
end

# ---- PortTerminal: lambdaf（输出函数）----
function _port_lambdaf_body()
    quote
        if !_has_updates && isempty(_pending_out_cargo)
            return
        end
        # 输出待装船货物（局部 _outbox）
        for c in _pending_out_cargo
            push!(_outbox, DEVSMessage(:o_cargo_out, c))
        end
        # 输出港口统计
        discharged_total = 0.0
        for c in discharged_cargo
            discharged_total += c.ffe
        end
        push!(_outbox, DEVSMessage(:o_stats, Main.Shipping.PortStats(
            port_code, _last_event_time, vessel_count, _loaded_total, discharged_total
        )))
    end
end

# ---- PortTerminal: deltint（内部转移）----
function _port_deltint_body()
    quote
        _pending_out_cargo = Main.Shipping.CargoBatch[]
        _has_updates = false
        _phase = :passive
        _sigma = INFINITY
    end
end

# ---- PortTerminal: deltext（外部转移）----
function _port_deltext_body()
    quote
        local e = dt
        triggered = false
        # 遍历局部 _inbox 中的消息
        for msg in _inbox
            if msg.port == :i_arrival
                evt = msg.value
                if evt.port_code == port_code
                    push!(arrivals, evt)
                    vessel_count = vessel_count + 1
                    _last_event_time = evt.sim_time
                    triggered = true
                end
            elseif msg.port == :i_departure
                evt = msg.value
                if evt.port_code == port_code
                    push!(departures, evt)
                    vessel_count = max(vessel_count - 1, 0)
                    _last_event_time = evt.sim_time
                    # 为离港船装载适配货物
                    loaded = Main.Shipping._load_for_vessel(cargo_buffer, evt, port_code, route_port_codes)
                    if !isempty(loaded)
                        for c in loaded
                            c.assigned_vessel = evt.vessel_name
                            push!(_pending_out_cargo, c)
                            _loaded_total = _loaded_total + c.ffe
                        end
                        cargo_buffer = Main.Shipping._remove_loaded(cargo_buffer, loaded)
                        triggered = true
                    end
                end
            elseif msg.port == :i_cargo_in
                cargo = msg.value
                if cargo.origin == port_code
                    push!(cargo_buffer, cargo)
                end
            elseif msg.port == :i_cargo_discharge
                cargo = msg.value
                if cargo.destination == port_code
                    push!(discharged_cargo, cargo)
                    _last_event_time = cargo.sim_time
                    triggered = true
                end
            end
        end
        if triggered
            _has_updates = true
            _sigma = 0.0  # activate
        end
        _sigma = _sigma - Float64(e)  # continuef
    end
end

# ---- DemandGenerator: ta 函数 ----
function _demand_ta_body()
    quote
        if _phase == :generating
            _sigma = 7.0
        else
            _sigma = INFINITY
        end
    end
end

# ---- DemandGenerator: lambdaf ----
function _demand_lambdaf_body()
    quote
        for od in od_list
            # 简单泊松近似: rand() 均匀分布, 落在 [0,1) 中低于 λ 的部分
            # Poisson-like sampling using Knuth algorithm
            lambda = od.ffe_per_week
            L = exp(-lambda)
            k = 0
            p = 1.0
            while true
                k += 1
                p *= rand()
                p < L && break
            end
            n_ffe = max(0, k - 1)
            if n_ffe <= 0
                continue
            end
            batch_counter = batch_counter + 1
            batch_id = string(route_id, "-W", current_week, "-", od.origin, "-", od.destination, "-", batch_counter)
            batch = Main.Shipping.CargoBatch(batch_id, od.origin, od.destination, Float64(n_ffe),
                od.revenue_per_unit, current_week;
                route_id=route_id,
                transit_time=od.transit_time)
            push!(_outbox, DEVSMessage(:o_demand, batch))
        end
    end
end

# ---- DemandGenerator: deltint ----
function _demand_deltint_body()
    quote
        current_week = current_week + 1
        if current_week >= max_weeks
            _phase = :passive
            _sigma = INFINITY
        else
            _phase = :generating
            _sigma = 7.0
        end
    end
end

# ---- DemandGenerator: deltext ----
function _demand_deltext_body()
    quote
        local e = dt
        _sigma = _sigma - Float64(e)
    end
end

# ============================================================
# 2. 全局状态变量列表（用于 compile_relation 的显式声明）
# ============================================================

const VESSEL_STATE_VARS = Symbol[
    :vessel_name, :route_data, :start_delay,
    :current_idx, :loaded_cargo,
    :disturbance_factor, :port_disturbance_factor,
    :_phase, :_sigma, :_inbox, :_outbox
]

const PORT_STATE_VARS = Symbol[
    :port_code, :route_port_codes,
    :arrivals, :departures,
    :cargo_buffer, :discharged_cargo,
    :_pending_out_cargo, :_loaded_total,
    :vessel_count, :_last_event_time, :_has_updates,
    :_phase, :_sigma, :_inbox, :_outbox
]

const DEMAND_STATE_VARS = Symbol[
    :od_list, :route_id, :max_weeks, :current_week,
    :batch_counter, :rng_seed,
    :_phase, :_sigma, :_inbox, :_outbox
]

# ============================================================
# 3. 模型工厂函数（返回 EntityDef）
# ============================================================

"""
    create_vessel(name, vessel_name, route, start_delay; disturbance_factor, port_disturbance_factor) -> EntityDef

创建一艘船舶的 EntityDef（DEVS 原子模型）。
disturbance_factor: 海航行时间扰动因子 (1.0=无扰动, >1=延迟)
port_disturbance_factor: 港口作业扰动因子 (1.0=无扰动, >1=延迟)
"""
function create_vessel(name::Symbol, vessel_name::String,
                       route::RouteSchedule, start_delay::Float64;
                       disturbance_factor::Float64=1.0,
                       port_disturbance_factor::Float64=1.0)
    ports = [
        Port(:i_cargo, Main.Shipping.CargoBatch, :in),
        Port(:o_arrival, Main.Shipping.VesselEvent, :out),
        Port(:o_departure, Main.Shipping.VesselEvent, :out),
        Port(:o_cargo_discharge, Main.Shipping.CargoBatch, :out),
    ]

    params = [
        Parameter(:vessel_name, vessel_name, String),
        Parameter(:route_data, route, Any),
        Parameter(:start_delay, start_delay, Float64),
        Parameter(:current_idx, 1, Int),  # 1-indexed port index
        Parameter(:loaded_cargo, Main.Shipping.CargoBatch[], Vector{Main.Shipping.CargoBatch}),
        # Disturbance factors for disruption-aware simulation
        Parameter(:disturbance_factor, disturbance_factor, Float64),
        Parameter(:port_disturbance_factor, port_disturbance_factor, Float64),
        # 船舶初始状态：立即进入 sailing 模式
        Parameter(:_phase, :sailing, Symbol),
        Parameter(:_sigma, 0.0, Float64),
        Parameter(:_inbox, DEVSMessage[], Vector{DEVSMessage}),
        Parameter(:_outbox, DEVSMessage[], Vector{DEVSMessage}),
    ]

    relations = [
        Relation(:ta, Behavioral, _vessel_ta_body(),
            [:devs_ta, :behavioral],
            Dict{Symbol,Any}(:state_vars => VESSEL_STATE_VARS)),
        Relation(:lambdaf, Behavioral, _vessel_lambdaf_body(),
            [:devs_lambdaf, :behavioral],
            Dict{Symbol,Any}(:state_vars => VESSEL_STATE_VARS)),
        Relation(:deltint, Behavioral, _vessel_deltint_body(),
            [:devs_deltint, :behavioral],
            Dict{Symbol,Any}(:state_vars => VESSEL_STATE_VARS)),
        Relation(:deltext, Behavioral, _vessel_deltext_body(),
            [:devs_deltext, :behavioral],
            Dict{Symbol,Any}(:state_vars => VESSEL_STATE_VARS)),
    ]

    return EntityDef(name, ports, relations, params)
end

"""
    create_port(name, port_code, route_port_codes) -> EntityDef

创建一个港口终端的 EntityDef（DEVS 原子模型）。
"""
function create_port(name::Symbol, port_code::String,
                     route_port_codes::Vector{String})
    ports = [
        Port(:i_arrival, Main.Shipping.VesselEvent, :in),
        Port(:i_departure, Main.Shipping.VesselEvent, :in),
        Port(:i_cargo_in, Main.Shipping.CargoBatch, :in),
        Port(:i_cargo_discharge, Main.Shipping.CargoBatch, :in),
        Port(:o_stats, Main.Shipping.PortStats, :out),
        Port(:o_cargo_out, Main.Shipping.CargoBatch, :out),
    ]

    params = [
        Parameter(:port_code, port_code, String),
        Parameter(:route_port_codes, route_port_codes, Vector{String}),
        Parameter(:arrivals, Main.Shipping.VesselEvent[], Vector{Main.Shipping.VesselEvent}),
        Parameter(:departures, Main.Shipping.VesselEvent[], Vector{Main.Shipping.VesselEvent}),
        Parameter(:cargo_buffer, Main.Shipping.CargoBatch[], Vector{Main.Shipping.CargoBatch}),
        Parameter(:discharged_cargo, Main.Shipping.CargoBatch[], Vector{Main.Shipping.CargoBatch}),
        Parameter(:_pending_out_cargo, Main.Shipping.CargoBatch[], Vector{Main.Shipping.CargoBatch}),
        Parameter(:_loaded_total, 0.0, Float64),
        Parameter(:vessel_count, 0, Int),
        Parameter(:_last_event_time, 0.0, Float64),
        Parameter(:_has_updates, false, Bool),
        Parameter(:_phase, PhaseInit, Symbol),
        Parameter(:_sigma, INFINITY, Float64),
        Parameter(:_inbox, DEVSMessage[], Vector{DEVSMessage}),
        Parameter(:_outbox, DEVSMessage[], Vector{DEVSMessage}),
    ]

    relations = [
        Relation(:ta, Behavioral, _port_ta_body(),
            [:devs_ta, :behavioral],
            Dict{Symbol,Any}(:state_vars => PORT_STATE_VARS)),
        Relation(:lambdaf, Behavioral, _port_lambdaf_body(),
            [:devs_lambdaf, :behavioral],
            Dict{Symbol,Any}(:state_vars => PORT_STATE_VARS)),
        Relation(:deltint, Behavioral, _port_deltint_body(),
            [:devs_deltint, :behavioral],
            Dict{Symbol,Any}(:state_vars => PORT_STATE_VARS)),
        Relation(:deltext, Behavioral, _port_deltext_body(),
            [:devs_deltext, :behavioral],
            Dict{Symbol,Any}(:state_vars => PORT_STATE_VARS)),
    ]

    return EntityDef(name, ports, relations, params)
end

"""
    create_demand_generator(name, od_list, route_id, seed, max_weeks) -> EntityDef

创建一个需求生成器的 EntityDef（DEVS 原子模型）。
"""
function create_demand_generator(name::Symbol, od_list::Vector{ODDemand},
                                 route_id::String; seed::Int=42, max_weeks::Int=52)
    ports = [
        Port(:o_demand, Main.Shipping.CargoBatch, :out),
    ]

    params = [
        Parameter(:od_list, od_list, Vector{Main.Shipping.ODDemand}),
        Parameter(:route_id, route_id, String),
        Parameter(:max_weeks, max_weeks, Int),
        Parameter(:current_week, 0, Int),
        Parameter(:batch_counter, 0, Int),
        Parameter(:rng_seed, seed, Int),
        # 需求生成器初始状态：立即进入生成模式（_sigma=0 触发第一步）
        Parameter(:_phase, :generating, Symbol),
        Parameter(:_sigma, 0.0, Float64),  # 立即生成第一周
        Parameter(:_inbox, DEVSMessage[], Vector{DEVSMessage}),
        Parameter(:_outbox, DEVSMessage[], Vector{DEVSMessage}),
    ]

    relations = [
        Relation(:ta, Behavioral, _demand_ta_body(),
            [:devs_ta, :behavioral],
            Dict{Symbol,Any}(:state_vars => DEMAND_STATE_VARS)),
        Relation(:lambdaf, Behavioral, _demand_lambdaf_body(),
            [:devs_lambdaf, :behavioral],
            Dict{Symbol,Any}(:state_vars => DEMAND_STATE_VARS)),
        Relation(:deltint, Behavioral, _demand_deltint_body(),
            [:devs_deltint, :behavioral],
            Dict{Symbol,Any}(:state_vars => DEMAND_STATE_VARS)),
        Relation(:deltext, Behavioral, _demand_deltext_body(),
            [:devs_deltext, :behavioral],
            Dict{Symbol,Any}(:state_vars => DEMAND_STATE_VARS)),
    ]

    return EntityDef(name, ports, relations, params)
end

# ============================================================
# 4. 耦合模型构建函数
# ============================================================

"""
    build_multi_vessel_route(name, route, vessel_count, first_vessel_week) -> (ComposeDef, entities_dict)

构建多船航线耦合模型。
返回 ComposeDef 和实体字典 (name → EntityDef)。
"""
function build_multi_vessel_route(name::Symbol, route::RouteSchedule;
                                  vessel_count::Int=15,
                                  first_vessel_week::Int=51,
                                  disturbance_factor::Float64=1.0,
                                  port_disturbance_factor::Float64=1.0)
    entities = EntityDef[]
    connections = Connection[]

    # 港口按唯一代码创建
    port_map = Dict{String, EntityDef}()
    route_ports = [pc.port_code for pc in route.port_calls]

    for pc in route.port_calls
        if !haskey(port_map, pc.port_code)
            pt_name = Symbol(string(route.route_id, "_PT_", pc.port_code))
            pt = create_port(pt_name, pc.port_code, route_ports)
            port_map[pc.port_code] = pt
            push!(entities, pt)
        end
    end

    # 创建船舶实例（带扰动因子）
    vessels = EntityDef[]
    for w in 0:(vessel_count-1)
        week_num = first_vessel_week + w
        v_name = Symbol(string(route.route_id, "-W", lpad(week_num, 2, '0')))
        v_str = string(route.route_id, "-W", lpad(week_num, 2, '0'))
        v = create_vessel(v_name, v_str, route, Float64(w * 7);
                          disturbance_factor=disturbance_factor,
                          port_disturbance_factor=port_disturbance_factor)
        push!(vessels, v)
    end
    append!(entities, vessels)

    # 外部端口
    # 用 exports 暴露内部端口
    exports = Tuple{String,Symbol,Symbol}[]

    # 内部耦合
    # 所有船舶的输出 → 对应港口 (通过端口名匹配，在 port 内部过滤)
    for v in vessels
        # 船舶 → 港口
        for (pc_code, pt) in port_map
            push!(connections, Connection((v.name, :o_arrival), (pt.name, :i_arrival)))
            push!(connections, Connection((v.name, :o_departure), (pt.name, :i_departure)))
            push!(connections, Connection((v.name, :o_cargo_discharge), (pt.name, :i_cargo_discharge)))
        end
    end

    # 所有港口的输出 → 所有船舶
    for (pc_code, pt) in port_map
        for v in vessels
            push!(connections, Connection((pt.name, :o_cargo_out), (v.name, :i_cargo)))
        end
    end

    # 构造 ComposeDef
    root = ComposeDef(name, entities, Relation[], connections, exports)
    return root
end

"""
    build_shipping_network(name, routes, route_od_map; kwargs...) -> ComposeDef

构建全局海运网络耦合模型。
"""
function build_shipping_network(name::Symbol, routes::Vector{RouteSchedule},
                                route_od_map::Dict{String, Vector{ODDemand}};
                                weeks_to_sim::Int=30,
                                vessels_per_route::Int=15,
                                first_week::Int=51,
                                seed::Int=42,
                                disturbance_factor::Float64=1.0,
                                port_disturbance_factor::Float64=1.0)
    all_entities = EntityDef[]
    all_connections = Connection[]
    all_exports = Tuple{String,Symbol,Symbol}[]

    for (i, route) in enumerate(routes)
        route_id = route.route_id
        ods = get(route_od_map, route_id, ODDemand[])

        # 需求生成器
        dg_name = Symbol(string(route_id, "_Demand"))
        dg = create_demand_generator(dg_name, ods, route_id,
            seed=seed + i * 100, max_weeks=weeks_to_sim)
        push!(all_entities, dg)

        # 多船航线（带扰动因子）
        rm = build_multi_vessel_route(
            Symbol(string(route_id, "_Route")),
            route,
            vessel_count=vessels_per_route,
            first_vessel_week=first_week,
            disturbance_factor=disturbance_factor,
            port_disturbance_factor=port_disturbance_factor,
        )
        # 展开 ComposeDef 的子实体和连接
        append!(all_entities, rm.entities)

        # 需求生成器 → 航线 (通过所有港口的 i_cargo_in 端口)
        for e in rm.entities
            for p in e.ports
                if p.name == :i_cargo_in
                    push!(all_connections, Connection((dg.name, :o_demand), (e.name, :i_cargo_in)))
                end
            end
        end

        # 收集该航线的所有内部连接
        append!(all_connections, rm.connections)
    end

    # 创建顶层 ComposeDef
    root = ComposeDef(name, all_entities, Relation[], all_connections, all_exports)
    return root
end

# ============================================================
# 5. 装载辅助函数（用于 PortTerminal 的 deltext 行为代码）
# ============================================================

"""
    _is_ahead_on_route(route_ports, port_code, destination, depart_order) -> Bool

判断目的港是否在当前港之后（航行方向上可达）。
"""
function _is_ahead_on_route(route_ports::Vector{String}, port_code::String,
                            destination::String, depart_order::Int)::Bool
    # 找到当前港的索引
    dep_idx = 0
    for (i, p) in enumerate(route_ports)
        if p == port_code && i >= depart_order
            dep_idx = i
            break
        end
    end
    dep_idx == 0 && return false

    # 找目的港的索引
    for (i, p) in enumerate(route_ports)
        if p == destination && i > dep_idx
            return true
        end
    end
    return false
end

"""
    _load_for_vessel(cargo_buffer, vessel_event, port_code, route_ports) -> Vector{CargoBatch}

为离港船筛选适配的货物。
"""
function _load_for_vessel(cargo_buffer::Vector{CargoBatch},
                          vessel_event::VesselEvent,
                          port_code::String,
                          route_ports::Vector{String})::Vector{CargoBatch}
    loaded = CargoBatch[]
    for c in cargo_buffer
        if c.origin == port_code &&
           _is_ahead_on_route(route_ports, port_code, c.destination, vessel_event.port_order)
            push!(loaded, c)
        end
    end
    return loaded
end

"""
    _remove_loaded(cargo_buffer, loaded) -> Vector{CargoBatch}

从 cargo_buffer 中移除已装载的货物。
"""
function _remove_loaded(cargo_buffer::Vector{CargoBatch},
                        loaded::Vector{CargoBatch})::Vector{CargoBatch}
    loaded_set = Set(loaded)
    return [c for c in cargo_buffer if !(c in loaded_set)]
end

# ============================================================
# 6. 数据加载函数
# ============================================================

"""
    load_route_schedules(filepath) -> Vector{RouteSchedule}

从 CSV 加载航线时刻表。
CSV 格式: RouteID, PortOrder, Port, ETA_day, ETD_day
"""
function load_route_schedules(filepath::String)::Vector{RouteSchedule}
    # 使用 CSV parsing
    lines = readlines(filepath)
    header = split(strip(lines[1]), ',')
    # 去掉 BOM
    header[1] = replace(header[1], "\ufeff" => "")

    routes = Dict{String, Vector{PortCall}}()

    for line in lines[2:end]
        isempty(strip(line)) && continue
        parts = split(strip(line), ',')
        route_id = strip(parts[1])
        port_order = parse(Int, strip(parts[2]))
        port = strip(parts[3])
        eta = parse(Float64, strip(parts[4]))
        etd_str = strip(parts[5])
        etd = isempty(etd_str) ? nothing : parse(Float64, etd_str)

        pc = PortCall(port, port_order, eta, etd)
        if !haskey(routes, route_id)
            routes[route_id] = PortCall[]
        end
        push!(routes[route_id], pc)
    end

    schedules = RouteSchedule[]
    for (route_id, calls) in routes
        sort!(calls; by = pc -> pc.port_order)
        total_days = maximum(pc -> pc.etd_day === nothing ? pc.eta_day : pc.etd_day, calls)
        push!(schedules, RouteSchedule(route_id, calls, total_days))
    end

    return schedules
end

"""
    load_od_demand(filepath) -> Vector{ODDemand}

从 CSV 加载 OD 需求数据。
CSV 格式: Origin, Destination, FFEPerWeek, Revenue_1, TransitTime (tab分隔)
"""
function load_od_demand(filepath::String)::Vector{ODDemand}
    lines = readlines(filepath)
    ods = ODDemand[]

    for line in lines[2:end]
        isempty(strip(line)) && continue
        parts = split(strip(line), '\t')
        length(parts) < 5 && continue
        origin = strip(parts[1])
        dest = strip(parts[2])
        ffe = parse(Float64, strip(parts[3]))
        revenue = parse(Float64, strip(parts[4]))
        transit = parse(Float64, strip(parts[5]))
        push!(ods, ODDemand(origin, dest, ffe, revenue, transit))
    end

    return ods
end

"""
    filter_ods_by_route(ods, route) -> Vector{ODDemand}

筛选出能被指定航线直接服务的 OD 对。
"""
function filter_ods_by_route(ods::Vector{ODDemand}, route::RouteSchedule)::Vector{ODDemand}
    route_ports = Set(ports(route))
    return [od for od in ods if od.origin in route_ports && od.destination in route_ports]
end

# ============================================================
# 6. Plan-Driven Model Construction (Decoupled from Optimization)
#
# Architecture:
#   ExecutionPlan (input) → build_simulation_model → ComposeDef (output)
#
# The simulation model does NOT know where the ExecutionPlan came from.
# It could be generated by:
#   - MILP optimization (optimization.jl)
#   - Manual configuration
#   - Random generation
#   - Historical data replay
#   - Any other "plan generator"
#
# This decouples the simulation from any specific optimization method.
# ============================================================

"""
    build_simulation_model(name, plan, schedules, route_od_map; kwargs...) -> ComposeDef

Build a simulation model from an ExecutionPlan. The plan specifies which services
are active, how many vessels each service deploys, and how demand is assigned.

This is the single entry point for simulation — it does not care whether the plan
came from optimization, manual configuration, or any other source.

# Arguments
- `name`: Symbol name for the root ComposeDef
- `plan`: ExecutionPlan specifying services, rotations, and demand assignments
- `schedules`: Vector of RouteSchedule for route topology
- `route_od_map`: Dict mapping route_id → ODDemand[] for demand generation

# Keyword Arguments
- `disturbance_factor`: Sailing time disturbance multiplier (1.0 = no disturbance)
- `port_disturbance_factor`: Port operation disturbance multiplier
- `seed`: Random seed for demand generators
- `weeks_to_sim`: Number of weeks for demand generation
"""
function build_simulation_model(name::Symbol,
                                plan::ExecutionPlan,
                                schedules::Vector{RouteSchedule},
                                route_od_map::Dict{String, Vector{ODDemand}};
                                disturbance_factor::Float64=1.0,
                                port_disturbance_factor::Float64=1.0,
                                seed::Int=42,
                                weeks_to_sim::Int=30)
    all_entities = EntityDef[]
    all_connections = Connection[]

    # Build lookup: route_id → RouteSchedule
    schedule_lookup = Dict(r.route_id => r for r in schedules)

    # 1. Create entities for each planned service
    for ps in plan.planned_services
        if !ps.is_active
            continue
        end

        route = get(schedule_lookup, ps.service_id, nothing)
        route === nothing && continue

        route_id = ps.service_id
        ods = get(route_od_map, route_id, ODDemand[])

        # Demand generator for this service
        dg_name = Symbol(string(route_id, "_Demand"))
        dg = create_demand_generator(dg_name, ods, route_id,
            seed=seed, max_weeks=weeks_to_sim)
        push!(all_entities, dg)

        # Build vessel route from plan's rotation data
        rm = build_multi_vessel_route(
            Symbol(string(route_id, "_Route")),
            route;
            vessel_count=ps.vessel_count,
            first_vessel_week=51,  # Default; could be overridden from plan
            disturbance_factor=disturbance_factor,
            port_disturbance_factor=port_disturbance_factor,
        )
        append!(all_entities, rm.entities)

        # Connect demand generator → ports
        for e in rm.entities
            for p in e.ports
                if p.name == :i_cargo_in
                    push!(all_connections, Connection((dg.name, :o_demand), (e.name, :i_cargo_in)))
                end
            end
        end

        # Collect internal connections
        append!(all_connections, rm.connections)
    end

    # 2. Create ComposeDef
    root = ComposeDef(name, all_entities, Relation[], all_connections, Tuple{String,Symbol,Symbol}[])
    return root
end

"""
    build_plan_from_config(schedules, route_od_map; config...) -> ExecutionPlan

Build an ExecutionPlan from simple configuration parameters (no optimization).
This is a "manual plan generator" — it creates a plan based on route schedules
and user-specified parameters like vessel counts.

This demonstrates that the simulation is decoupled from optimization:
the same simulation model can be driven by any plan source.
"""
function build_plan_from_config(schedules::Vector{RouteSchedule},
                                route_od_map::Dict{String, Vector{ODDemand}};
                                vessels_per_route::Int=5,
                                first_week::Int=51,
                                cycle_days::Int=7,
                                scenario_id::String="manual",
                                description::String="Manually configured plan")
    planned_services = PlannedService[]
    planned_rotations = PlannedVesselRotation[]
    planned_assignments = PlannedDemandAssignment[]

    for route in schedules
        route_id = route.route_id
        total_days = max(1, ceil(Int, route.total_days))
        required_vessels = max(1, cld(total_days, cycle_days))
        actual_vessels = min(vessels_per_route, required_vessels)

        # Planned service
        push!(planned_services, PlannedService(route_id, "default", actual_vessels, true))

        # Planned rotations
        for v_idx in 0:(actual_vessels - 1)
            vessel_name = string(route_id, "-W", lpad(string(first_week + v_idx), 2, '0'))
            start_delay = Float64(v_idx * cycle_days)
            push!(planned_rotations, PlannedVesselRotation(
                vessel_name, route_id, "default", start_delay,
                [PlannedCall(pc.port_code, start_delay + pc.eta_day,
                             pc.etd_day !== nothing ? start_delay + pc.etd_day : start_delay + pc.eta_day,
                             pc.port_order) for pc in route.port_calls],
            ))
        end

        # Planned demand assignments (simplified: all ODs accepted)
        ods = get(route_od_map, route_id, ODDemand[])
        for (idx, od) in enumerate(ods)
            demand_id = string("D-", route_id, "-", lpad(idx, 3, '0'))
            push!(planned_assignments, PlannedDemandAssignment(
                demand_id, od.origin, od.destination, od.ffe_per_week,
                PlannedPathLeg[],  # Path details not specified in manual mode
            ))
        end
    end

    meta = PlanMeta(
        "manual", scenario_id,
        cycle_days, 8,
        string(Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS")),
        0.0, :manual,
    )

    return ExecutionPlan(meta, planned_services, planned_rotations, planned_assignments)
end

"""
    build_plan_from_schedules(schedules; vessels_per_route, first_week, cycle_days) -> ExecutionPlan

Convenience: build a plan directly from schedules without OD data.
Creates a minimal plan with just service and rotation info.
"""
function build_plan_from_schedules(schedules::Vector{RouteSchedule};
                                   vessels_per_route::Int=5,
                                   first_week::Int=51,
                                   cycle_days::Int=7)
    route_od_map = Dict{String, Vector{ODDemand}}(r.route_id => ODDemand[] for r in schedules)
    return build_plan_from_config(schedules, route_od_map;
                                  vessels_per_route=vessels_per_route,
                                  first_week=first_week,
                                  cycle_days=cycle_days,
                                  scenario_id="schedules_only")
end

println("[ShippingModels] 海运 DEVS 模型已加载。")
