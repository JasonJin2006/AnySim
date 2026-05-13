"use client";

import type { ExtensionViewProps } from "../../types";
import type {
  ExperimentSummaryData,
  KpiData,
  EconomicBreakdownData,
  RobustnessData,
  TimeSeriesPointData,
} from "@/protocol/types";

function readNumber(v: unknown, digits = 1): string {
  return typeof v === "number" ? v.toFixed(digits) : "--";
}

function readCurrency(v: unknown): string {
  return typeof v === "number" ? `$${(v / 1000).toFixed(1)}K` : "--";
}

function readPercent(v: unknown): string {
  return typeof v === "number" ? `${(v * 100).toFixed(1)}%` : "--";
}

/** KPI 卡片 */
function KpiCard({
  label,
  value,
  unit,
  accent,
}: {
  label: string;
  value: string;
  unit?: string;
  accent?: boolean;
}) {
  return (
    <div
      className="flex flex-col gap-1 border border-white/6 px-3 py-2"
      style={{ background: accent ? "rgba(59,130,246,0.08)" : "transparent" }}
    >
      <span className="text-[9px] uppercase tracking-[0.18em] text-white/[0.38]">
        {label}
      </span>
      <span className="text-[15px] font-medium text-white">
        {value}
        {unit && (
          <span className="ml-1 text-[10px] text-white/[0.4]">{unit}</span>
        )}
      </span>
    </div>
  );
}

/** 经济分解条 */
function EconBar({
  label,
  value,
  total,
  isCost,
}: {
  label: string;
  value: number;
  total: number;
  isCost: boolean;
}) {
  const pct = total > 0 ? Math.min((Math.abs(value) / total) * 100, 100) : 0;
  return (
    <div className="flex items-center gap-2 text-[11px]">
      <span className="w-28 shrink-0 text-white/[0.56]">{label}</span>
      <div
        className="h-1.5 flex-1 rounded-full"
        style={{ background: "rgba(255,255,255,0.06)" }}
      >
        <div
          className="h-full rounded-full"
          style={{
            width: `${pct}%`,
            background: isCost ? "rgba(239,68,68,0.6)" : "rgba(34,197,94,0.6)",
          }}
        />
      </div>
      <span className={isCost ? "text-red-400" : "text-emerald-400"}>
        {readCurrency(value)}
      </span>
    </div>
  );
}

/** 迷你时间序列图 */
function MiniTimeSeries({
  ts,
  color,
}: {
  ts: TimeSeriesPointData;
  color: string;
}) {
  if (!ts.points || ts.points.length < 2) return null;
  const vals = ts.points.map((p) => p[1]);
  const minV = Math.min(...vals);
  const maxV = Math.max(...vals);
  const range = maxV - minV || 1;
  const w = 200;
  const h = 40;
  const pathD = ts.points
    .map((p, i) => {
      const x = (i / (ts.points.length - 1)) * w;
      const y = h - ((p[1] - minV) / range) * h;
      return `${i === 0 ? "M" : "L"}${x},${y}`;
    })
    .join(" ");

  return (
    <div className="flex flex-col gap-1">
      <span className="text-[9px] text-white/[0.5]">
        {ts.metric_name} {ts.unit && `(${ts.unit})`}
      </span>
      <svg width={w} height={h} className="overflow-visible">
        <path d={pathD} fill="none" stroke={color} strokeWidth="1.5" />
      </svg>
    </div>
  );
}

export function ExperimentResultView({ context }: ExtensionViewProps) {
  // 从 outputPorts 中获取实验结果
  const experimentPort = context.outputPorts.find(
    (p) => p.id === "experiment-result",
  );
  const comparisonPort = context.outputPorts.find(
    (p) => p.id === "model-comparison",
  );
  const robustnessPort = context.outputPorts.find(
    (p) => p.id === "robustness-analysis",
  );

  const expData = experimentPort?.data as Record<string, unknown> | undefined;
  const compData = comparisonPort?.data as Record<string, unknown> | undefined;
  const robData = robustnessPort?.data as Record<string, unknown> | undefined;

  const kpi = expData?.kpi as KpiData | undefined;
  const econ = expData?.economic_breakdown as EconomicBreakdownData | undefined;
  const tsData = expData?.time_series as
    | Record<string, TimeSeriesPointData>
    | undefined;
  const robustness = robData?.data as RobustnessData | undefined;

  if (!expData && !compData && !robustnessPort) {
    return (
      <section className="flex h-full items-center justify-center border border-white/6 bg-[rgba(11,15,22,0.92)]">
        <div className="text-center">
          <p className="text-[12px] text-white/[0.4]">
            No experiment result yet
          </p>
          <p className="mt-1 text-[10px] text-white/[0.25]">
            Run an experiment to see results here
          </p>
        </div>
      </section>
    );
  }

  return (
    <section className="flex flex-col gap-3 border border-white/6 bg-[rgba(11,15,22,0.92)] p-4">
      {/* Header */}
      <div className="flex items-center justify-between border-b border-white/6 pb-2">
        <div>
          <p className="text-[10px] uppercase tracking-[0.2em] text-white/[0.34]">
            Experiment Result
          </p>
          <h3 className="mt-0.5 text-[16px] text-white">
            {String(expData?.model_name ?? "--")} /{" "}
            {String(expData?.scenario_id ?? "--")}
          </h3>
        </div>
        {expData?.disruption_level !== undefined && (
          <span className="border border-white/10 px-2 py-0.5 text-[9px] text-white/[0.5]">
            Disruption: {readNumber(expData.disruption_level, 1)}
          </span>
        )}
      </div>

      {/* KPI Cards */}
      {kpi && (
        <div className="grid grid-cols-4 gap-2">
          <KpiCard
            label="Simulated Profit"
            value={readCurrency(kpi.simulated_profit)}
            accent
          />

          <KpiCard
            label="Profit Retention"
            value={readPercent(kpi.profit_retention_rate)}
            accent
          />

          <KpiCard
            label="On-Time Delivery"
            value={readPercent(kpi.on_time_delivery_rate)}
          />

          <KpiCard
            label="Service Reliability"
            value={readPercent(kpi.service_reliability)}
          />

          <KpiCard
            label="Avg Utilization"
            value={readPercent(kpi.avg_utilization)}
          />

          <KpiCard
            label="Rejection Rate"
            value={readPercent(kpi.rejection_rate)}
          />

          <KpiCard
            label="Delivered FFE"
            value={readNumber(kpi.delivered_cargo_ffe, 0)}
            unit="FFE"
          />

          <KpiCard
            label="Avg Transit"
            value={readNumber(kpi.avg_transit_time, 1)}
            unit="days"
          />
        </div>
      )}

      {/* Economic Breakdown */}
      {econ && (
        <div className="flex flex-col gap-1.5 border-t border-white/6 pt-3">
          <p className="text-[10px] uppercase tracking-[0.18em] text-white/[0.34]">
            Economic Breakdown
          </p>
          <EconBar
            label="Cargo Revenue"
            value={econ.cargo_revenue}
            total={econ.cargo_revenue}
            isCost={false}
          />

          <EconBar
            label="Fleet Cost"
            value={econ.fleet_deployment_cost}
            total={econ.cargo_revenue}
            isCost
          />

          <EconBar
            label="Sea Transport"
            value={econ.sea_transport_cost}
            total={econ.cargo_revenue}
            isCost
          />

          <EconBar
            label="Port Handling"
            value={econ.port_handling_cost}
            total={econ.cargo_revenue}
            isCost
          />

          <EconBar
            label="Late Penalty"
            value={econ.late_penalty}
            total={econ.cargo_revenue}
            isCost
          />

          <div className="mt-1 border-t border-white/6 pt-1">
            <EconBar
              label="Net Profit"
              value={econ.net_profit}
              total={econ.cargo_revenue}
              isCost={false}
            />
          </div>
        </div>
      )}

      {/* Time Series */}
      {tsData && Object.keys(tsData).length > 0 && (
        <div className="flex flex-col gap-2 border-t border-white/6 pt-3">
          <p className="text-[10px] uppercase tracking-[0.18em] text-white/[0.34]">
            Time Series
          </p>
          <div className="grid grid-cols-3 gap-3">
            {Object.entries(tsData).map(([key, ts]) => (
              <MiniTimeSeries key={key} ts={ts} color="#3b82f6" />
            ))}
          </div>
        </div>
      )}

      {/* Robustness */}
      {robustness && (
        <div className="flex flex-col gap-2 border-t border-white/6 pt-3">
          <p className="text-[10px] uppercase tracking-[0.18em] text-white/[0.34]">
            Robustness Analysis
          </p>
          <div className="grid grid-cols-3 gap-2">
            <KpiCard
              label="Robustness Score"
              value={readPercent(robustness.robustness_score)}
              accent
            />

            <KpiCard
              label="Profit Retention"
              value={readPercent(robustness.profit_retention)}
            />

            <KpiCard
              label="On-Time Degradation"
              value={readNumber(robustness.on_time_degradation_slope, 3)}
              unit="/level"
            />
          </div>
        </div>
      )}

      {/* Model Comparison */}
      {compData?.models && Array.isArray(compData.models) && (
        <div className="flex flex-col gap-2 border-t border-white/6 pt-3">
          <p className="text-[10px] uppercase tracking-[0.18em] text-white/[0.34]">
            Model Comparison
          </p>
          <div className="overflow-x-auto">
            <table className="w-full text-[11px]">
              <thead>
                <tr className="border-b border-white/6 text-white/[0.4]">
                  <th className="px-2 py-1 text-left">Model</th>
                  <th className="px-2 py-1 text-right">Profit</th>
                  <th className="px-2 py-1 text-right">On-Time</th>
                  <th className="px-2 py-1 text-right">Utilization</th>
                  <th className="px-2 py-1 text-right">Rejection</th>
                </tr>
              </thead>
              <tbody>
                {(compData.models as ExperimentSummaryData[]).map((m) => (
                  <tr key={m.experiment_id} className="border-b border-white/4">
                    <td className="px-2 py-1 text-white">{m.model_name}</td>
                    <td className="px-2 py-1 text-right text-emerald-400">
                      {readCurrency(m.economic_breakdown?.net_profit)}
                    </td>
                    <td className="px-2 py-1 text-right">
                      {readPercent(m.kpi?.on_time_delivery_rate)}
                    </td>
                    <td className="px-2 py-1 text-right">
                      {readPercent(m.kpi?.avg_utilization)}
                    </td>
                    <td className="px-2 py-1 text-right text-red-400">
                      {readPercent(m.kpi?.rejection_rate)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </section>
  );
}
