"use client";

export type SimMode = "academic" | "real_time";

interface ControlPanelProps {
  running: boolean;
  paused: boolean;
  speed: number;
  mode: SimMode;
  currentTime?: number;
  stepCount?: number;
  onStart: () => void;
  onPause: () => void;
  onResume: () => void;
  onReset: () => void;
  onStep?: () => void;
  onSpeedChange: (speed: number) => void;
  onModeChange: (mode: SimMode) => void;
  disabled?: boolean;
}

export function ControlPanel({
  running,
  paused,
  speed,
  mode,
  currentTime = 0,
  stepCount = 0,
  onStart,
  onPause,
  onResume,
  onReset,
  onStep,
  onSpeedChange,
  onModeChange,
  disabled = false,
}: ControlPanelProps) {
  const runtimeLabel = !running ? "Idle" : paused ? "Paused" : "Running";

  return (
    <div
      className="pointer-events-auto flex min-w-[640px] items-stretch border"
      style={{
        background: "var(--panel-bg)",
        borderColor: "var(--border-color)",
        boxShadow: "var(--shadow-lg)",
        color: "var(--text-main)",
      }}
    >
      <div className="flex items-stretch">
        {!running ? (
          <IconButton
            title="Start"
            onClick={() => onStart()}
            disabled={disabled}
          >
            <PlayIcon />
          </IconButton>
        ) : paused ? (
          <IconButton title="Resume" onClick={() => onResume()}>
            <PlayIcon />
          </IconButton>
        ) : (
          <IconButton title="Pause" onClick={() => onPause()}>
            <PauseIcon />
          </IconButton>
        )}

        <IconButton
          title="Reset"
          onClick={() => onReset()}
          disabled={disabled && !running}
        >
          <ResetIcon />
        </IconButton>

        {onStep ? (
          <IconButton
            title="Step"
            onClick={() => onStep()}
            disabled={!running || !paused}
          >
            <StepIcon />
          </IconButton>
        ) : null}
      </div>

      <div
        className="w-px self-stretch"
        style={{ background: "var(--border-color)" }}
      />

      <div className="flex min-w-[240px] flex-1 items-center gap-2 px-2">
        <div
          className="shrink-0 text-[9px]"
          style={{ color: "var(--text-secondary)" }}
        >
          {runtimeLabel}
        </div>
        <input
          type="range"
          min="0.1"
          max="100"
          step="0.1"
          value={speed}
          onChange={(event) => onSpeedChange(parseFloat(event.target.value))}
          className="speed-slider h-1 w-full appearance-none rounded-full outline-none"
          style={{ background: "var(--panel-strong)" }}
        />

        <div
          className="shrink-0 text-[9px]"
          style={{ color: "var(--text-main)" }}
        >
          {speed.toFixed(speed < 1 ? 1 : 0)}x
        </div>
      </div>

      <div
        className="w-px self-stretch"
        style={{ background: "var(--border-color)" }}
      />

      <div
        className="flex items-center gap-3 px-2 text-[9px]"
        style={{ color: "var(--text-secondary)" }}
      >
        <span>
          Time{" "}
          <span style={{ color: "var(--text-main)" }}>
            {fmtTime(currentTime)}
          </span>
        </span>
        <span>
          Steps{" "}
          <span style={{ color: "var(--text-main)" }}>
            {stepCount.toLocaleString()}
          </span>
        </span>
      </div>

      <div
        className="w-px self-stretch"
        style={{ background: "var(--border-color)" }}
      />

      <div className="flex items-stretch">
        <ModePill
          active={mode === "academic"}
          onClick={() => onModeChange("academic")}
        >
          Academic
        </ModePill>
        <ModePill
          active={mode === "real_time"}
          onClick={() => onModeChange("real_time")}
        >
          Realtime
        </ModePill>
      </div>
    </div>
  );
}

function IconButton({
  children,
  title,
  onClick,
  disabled = false,
}: {
  children: React.ReactNode;
  title: string;
  onClick: () => void;
  disabled?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      title={title}
      className="flex h-8 w-8 items-center justify-center border-r disabled:opacity-35"
      style={{
        borderColor: "var(--border-color)",
        background: "transparent",
        color: "var(--text-main)",
      }}
    >
      {children}
    </button>
  );
}

function ModePill({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      className="border-l px-2 text-[9px]"
      style={{
        borderColor: "var(--border-color)",
        background: active ? "var(--accent-soft)" : "transparent",
        color: active ? "var(--text-main)" : "var(--text-secondary)",
      }}
    >
      {children}
    </button>
  );
}

function PlayIcon() {
  return (
    <svg
      width="12"
      height="12"
      viewBox="0 0 24 24"
      fill="currentColor"
      aria-hidden="true"
    >
      <path d="m8 5 11 7-11 7V5Z" />
    </svg>
  );
}

function PauseIcon() {
  return (
    <svg
      width="12"
      height="12"
      viewBox="0 0 24 24"
      fill="currentColor"
      aria-hidden="true"
    >
      <rect x="6" y="5" width="4" height="14" rx="1" />
      <rect x="14" y="5" width="4" height="14" rx="1" />
    </svg>
  );
}

function ResetIcon() {
  return (
    <svg
      width="12"
      height="12"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M3 12a9 9 0 1 0 3-6.7" />
      <path d="M3 4v5h5" />
    </svg>
  );
}

function StepIcon() {
  return (
    <svg
      width="12"
      height="12"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M6 5v14" />
      <path d="m10 8 8 4-8 4V8Z" fill="currentColor" stroke="none" />
    </svg>
  );
}

function fmtTime(t: number) {
  const days = Math.floor(t / 24);
  const hours = Math.floor(t % 24);
  return `D${days + 1} ${hours.toString().padStart(2, "0")}:00`;
}
