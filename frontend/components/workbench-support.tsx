"use client";

import type { ReactNode } from "react";

export function EmptyBlock({
  title,
  description,
}: {
  title: string;
  description: string;
}) {
  return (
    <div
      className="rounded-md border border-dashed p-3"
      style={{
        borderColor: "var(--border-color)",
        background: "var(--panel-subtle)",
      }}
    >
      <div className="text-[11px]" style={{ color: "var(--text-main)" }}>
        {title}
      </div>
      <p
        className="mt-1 text-[10px] leading-5"
        style={{ color: "var(--text-secondary)" }}
      >
        {description}
      </p>
    </div>
  );
}

export function MetricMini({ label, value }: { label: string; value: string }) {
  return (
    <div
      className="rounded-md border px-3 py-2"
      style={{
        background: "var(--panel-subtle)",
        borderColor: "var(--border-color)",
      }}
    >
      <div
        className="text-[10px] uppercase tracking-[0.14em]"
        style={{ color: "var(--text-tertiary)" }}
      >
        {label}
      </div>
      <div
        className="mt-1 font-display text-[18px]"
        style={{ color: "var(--text-main)" }}
      >
        {value}
      </div>
    </div>
  );
}

export function Tag({
  children,
  tone = "neutral",
}: {
  children: ReactNode;
  tone?: "neutral" | "warm" | "cool";
}) {
  const toneClass =
    tone === "warm"
      ? "border-[rgba(240,140,0,0.35)] text-[#ffd08a]"
      : tone === "cool"
        ? "border-[rgba(76,110,245,0.32)] text-[#c5d2ff]"
        : "border-[var(--border-color)] text-[var(--text-secondary)]";

  return (
    <span
      className={`rounded-[6px] border px-1.5 py-0.5 text-[9px] uppercase tracking-[0.1em] ${toneClass}`}
    >
      {children}
    </span>
  );
}

export function ProjectPanel({
  connected,
  projectPath,
  activePresetId,
  presets,
  activeExtensionLabel,
  onLoadPreset,
}: {
  connected: boolean;
  projectPath: string | null;
  activePresetId: string | null;
  presets: Array<{ id: string; label: string; description?: string }>;
  activeExtensionLabel: string | null;
  onLoadPreset: (presetId: string) => void;
}) {
  return (
    <div className="space-y-2">
      <div
        className="rounded-md border p-2"
        style={{
          background: "var(--panel-subtle)",
          borderColor: "var(--border-color)",
        }}
      >
        <div
          className="text-[10px] uppercase tracking-[0.14em]"
          style={{ color: "var(--text-tertiary)" }}
        >
          Project Package
        </div>
        <div
          className="mt-1 text-[11px] leading-5"
          style={{ color: "var(--text-secondary)" }}
        >
          {projectPath ??
            (connected
              ? "Runtime connected without explicit project package metadata."
              : "Connect a runtime to inspect project packages.")}
        </div>
        {activeExtensionLabel ? (
          <div
            className="mt-2 text-[10px] uppercase tracking-[0.12em]"
            style={{ color: "var(--text-tertiary)" }}
          >
            Extension: {activeExtensionLabel}
          </div>
        ) : null}
      </div>
      <div className="space-y-1">
        {presets.map((preset) => (
          <button
            key={preset.id}
            onClick={() => onLoadPreset(preset.id)}
            className="w-full rounded-md border px-2.5 py-2 text-left transition"
            style={{
              borderColor:
                activePresetId === preset.id
                  ? "var(--accent)"
                  : "var(--border-color)",
              background:
                activePresetId === preset.id
                  ? "var(--accent-soft)"
                  : "var(--panel-subtle)",
            }}
          >
            <div className="text-[11px]" style={{ color: "var(--text-main)" }}>
              {preset.label}
            </div>
            <div
              className="mt-1 text-[10px] leading-5"
              style={{ color: "var(--text-secondary)" }}
            >
              {preset.description ?? preset.id}
            </div>
          </button>
        ))}
        {presets.length === 0 ? (
          <EmptyBlock
            title="No presets loaded"
            description="The runtime can expose project-backed presets here once get_presets is available."
          />
        ) : null}
      </div>
    </div>
  );
}
