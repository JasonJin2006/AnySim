"use client";

export function ConnectOverlay({
  presets,
  activePresetId,
  onLoadPreset,
  onConnect,
  onClose,
}: {
  presets: Array<{ id: string; label: string; description?: string }>;
  activePresetId: string | null;
  onLoadPreset: (presetId: string) => void;
  onConnect: (url: string) => void;
  onClose: () => void;
}) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-[rgba(15,23,42,0.32)] px-4 backdrop-blur-sm">
      <div
        className="w-full max-w-md border p-6"
        style={{
          background: "var(--panel-bg)",
          borderColor: "var(--border-color)",
          boxShadow: "var(--shadow-lg)",
        }}
      >
        <div
          className="text-[10px] uppercase tracking-[0.18em]"
          style={{ color: "var(--text-tertiary)" }}
        >
          Runtime Link
        </div>
        <h3
          className="mt-3 font-display text-[28px]"
          style={{ color: "var(--text-main)" }}
        >
          连接仿真后端
        </h3>
        <p
          className="mt-2 text-[13px] leading-6"
          style={{ color: "var(--text-secondary)" }}
        >
          这里连接的只是执行层。工作台本身仍然独立存在，后续可以继续封装为本地桌面应用。
        </p>

        <div className="mt-5 space-y-2">
          <label
            className="text-[11px] uppercase tracking-[0.14em]"
            style={{ color: "var(--text-tertiary)" }}
          >
            Project Preset
          </label>
          <select
            value={activePresetId ?? ""}
            onChange={(event) => {
              if (event.target.value) onLoadPreset(event.target.value);
            }}
            className="w-full rounded-md border px-4 py-3 text-sm outline-none transition"
            style={{
              background: "var(--workspace-bg)",
              borderColor: "var(--border-color)",
              color: "var(--text-main)",
            }}
          >
            <option value="" disabled>
              Select a preset
            </option>
            {presets.map((preset) => (
              <option
                key={preset.id}
                value={preset.id}
                style={{
                  background: "var(--panel-bg)",
                  color: "var(--text-main)",
                }}
              >
                {preset.label}
              </option>
            ))}
          </select>
          {activePresetId ? (
            <p
              className="text-[12px] leading-5"
              style={{ color: "var(--text-secondary)" }}
            >
              {presets.find((preset) => preset.id === activePresetId)
                ?.description ?? activePresetId}
            </p>
          ) : null}
        </div>

        <div className="mt-5 space-y-2">
          <label
            className="text-[11px] uppercase tracking-[0.14em]"
            style={{ color: "var(--text-tertiary)" }}
          >
            WebSocket URL
          </label>
          <input
            defaultValue="ws://127.0.0.1:8080/ws/sim"
            id="connect-url"
            className="w-full rounded-md border px-4 py-3 text-sm outline-none transition"
            style={{
              background: "var(--workspace-bg)",
              borderColor: "var(--border-color)",
              color: "var(--text-main)",
            }}
            placeholder="ws://host:port/ws/sim"
          />
        </div>

        <div className="mt-6 flex flex-col gap-3 sm:flex-row">
          <button
            onClick={() => {
              const input = document.getElementById(
                "connect-url",
              ) as HTMLInputElement;
              onConnect(input?.value || "ws://127.0.0.1:8080/ws/sim");
            }}
            className="btn-primary flex-1"
          >
            Connect backend
          </button>
          <button
            onClick={() => onConnect("mock")}
            className="btn-ghost flex-1"
          >
            Use mock runtime
          </button>
        </div>

        <button
          onClick={onClose}
          className="mt-4 w-full text-center text-sm transition"
          style={{ color: "var(--text-secondary)" }}
        >
          取消
        </button>
      </div>
    </div>
  );
}

export function WorkbenchContextMenu({
  x,
  y,
  scope,
  onClose,
  onAction,
}: {
  x: number;
  y: number;
  scope: string;
  onClose: () => void;
  onAction: (
    action: "reset-layout" | "open-connect" | "focus-explorer",
  ) => void;
}) {
  return (
    <div
      className="fixed z-50 min-w-[180px] border p-1"
      style={{
        left: Math.min(x, window.innerWidth - 220),
        top: Math.min(y, window.innerHeight - 180),
      }}
      onContextMenu={(event) => event.preventDefault()}
      onMouseLeave={onClose}
    >
      <div
        className="absolute inset-0 -z-10"
        style={{
          background: "var(--panel-bg)",
          border: "1px solid var(--border-color)",
          boxShadow: "var(--shadow-lg)",
        }}
      />

      <div
        className="px-2 py-1 text-[9px] uppercase tracking-[0.16em]"
        style={{ color: "var(--text-tertiary)" }}
      >
        {scope}
      </div>
      <button className="menu-item" onClick={() => onAction("focus-explorer")}>
        Focus Explorer
      </button>
      <button className="menu-item" onClick={() => onAction("open-connect")}>
        Open Runtime Link
      </button>
      <button className="menu-item" onClick={() => onAction("reset-layout")}>
        Reset Layout
      </button>
    </div>
  );
}
