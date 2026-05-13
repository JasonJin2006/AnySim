"use client";

import type { ConnectionStatus } from "@/hooks/useSimulation";

interface StatusBarProps {
  connectionStatus: ConnectionStatus;
  running: boolean;
  paused: boolean;
  currentTime: number;
  stepCount: number;
  speed: number;
  entityCount: number;
  modelName?: string;
  onReconnect?: () => void;
}

export function StatusBar({
  connectionStatus,
  running,
  paused,
  currentTime,
  stepCount,
  speed,
  entityCount,
  modelName,
  onReconnect,
}: StatusBarProps) {
  const connectionMeta: Record<
    ConnectionStatus,
    { label: string; dot: string }
  > = {
    disconnected: { label: "Offline", dot: "bg-slate-400" },
    connecting: { label: "Connecting", dot: "bg-amber-400" },
    connected: { label: "Linked", dot: "bg-emerald-400" },
    error: { label: "Fault", dot: "bg-rose-400" },
  };

  const runtimeLabel = !running ? "Idle" : paused ? "Paused" : "Running";
  const runtimeTone = !running
    ? "var(--text-secondary)"
    : paused
      ? "#f59f00"
      : "#40c057";

  return (
    <div
      className="statusbar flex flex-col gap-2 border px-3 py-2.5 text-[11px] sm:flex-row sm:items-center sm:justify-between"
      style={{
        background: "var(--panel-bg)",
        borderColor: "var(--border-color)",
        color: "var(--text-secondary)",
      }}
    >
      <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
        <StatusPill
          label="Link"
          value={connectionMeta[connectionStatus].label}
          dotClass={connectionMeta[connectionStatus].dot}
        />

        <StatusPill
          label="Runtime"
          value={runtimeLabel}
          dotClass={
            !running
              ? "bg-white/30"
              : paused
                ? "bg-amber-300"
                : "bg-emerald-300 animate-pulse"
          }
          valueClass={runtimeTone}
        />

        {modelName ? <StatusPill label="Model" value={modelName} /> : null}
      </div>

      <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
        <StatusMetric label="Clock" value={fmtTime(currentTime)} />

        <StatusMetric label="Steps" value={stepCount.toLocaleString()} />

        <StatusMetric
          label="Speed"
          value={`${speed.toFixed(speed < 1 ? 1 : 0)}x`}
        />

        <StatusMetric label="Entities" value={String(entityCount)} />

        {connectionStatus === "error" && onReconnect ? (
          <button
            onClick={onReconnect}
            className="rounded-full border border-rose-400/[0.35] px-2.5 py-1 text-[10px] text-rose-200 transition hover:border-rose-300 hover:text-white"
          >
            Retry link
          </button>
        ) : null}
      </div>
    </div>
  );
}

function StatusPill({
  label,
  value,
  dotClass,
  valueClass,
}: {
  label: string;
  value: string;
  dotClass?: string;
  valueClass?: string;
}) {
  return (
    <div
      className="flex items-center gap-2 rounded-md border px-2.5 py-1"
      style={{
        background: "var(--panel-subtle)",
        borderColor: "var(--border-color)",
      }}
    >
      {dotClass ? (
        <span className={`h-2 w-2 rounded-full ${dotClass}`} />
      ) : null}
      <span
        className="uppercase tracking-[0.14em]"
        style={{ color: "var(--text-tertiary)" }}
      >
        {label}
      </span>
      <span style={{ color: valueClass ?? "var(--text-main)" }}>{value}</span>
    </div>
  );
}

function StatusMetric({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center gap-2">
      <span
        className="uppercase tracking-[0.14em]"
        style={{ color: "var(--text-tertiary)" }}
      >
        {label}
      </span>
      <span className="font-mono" style={{ color: "var(--text-main)" }}>
        {value}
      </span>
    </div>
  );
}

function fmtTime(t: number) {
  const days = Math.floor(t / 24);
  const hours = Math.floor(t % 24);
  return `D${days + 1} ${hours.toString().padStart(2, "0")}:00`;
}
