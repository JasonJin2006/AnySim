import type { ExtensionViewProps } from "../../types";

function isVesselEntity(name: string): boolean {
  return (
    name.startsWith("Vessel_") ||
    /^AEU\d+-W\d+$/.test(name) ||
    name.includes("-W")
  );
}

function readStr(value: unknown): string {
  return value != null ? String(value) : "--";
}

export function VesselTimelineView({ context }: ExtensionViewProps) {
  const allNames = Array.from(context.entityCache.getAllEntities().keys());
  const vesselNames = allNames.filter(isVesselEntity);
  const currentTime = context.runner.currentTime;

  // Show first vessel as primary, list others
  const primaryName = vesselNames[0] ?? null;
  const primaryState = primaryName
    ? context.entityCache.getEntity(primaryName)
    : null;

  // Build timeline from route data if available
  const currentIdx =
    typeof primaryState?.current_idx === "number"
      ? primaryState.current_idx
      : 0;
  const phase = primaryState?._phase ? String(primaryState._phase) : "--";
  const sigma =
    typeof primaryState?._sigma === "number" ? primaryState._sigma : 0;

  const timeline = [
    {
      label: "Depart Origin",
      time: Math.max(0, currentTime - 8).toFixed(1),
      active: currentIdx >= 1,
    },
    {
      label: "At Sea",
      time: Math.max(0, currentTime - 4).toFixed(1),
      active: currentIdx >= 1 && phase === "sailing",
    },
    {
      label: phase === "in_port" ? "In Port" : "Next Arrival",
      time: currentTime.toFixed(1),
      active: true,
    },
    {
      label: "Next Departure",
      time: (currentTime + sigma).toFixed(1),
      active: false,
    },
  ];

  return (
    <section className="border border-white/8 bg-[rgba(11,15,22,0.92)]">
      <div className="border-b border-white/8 px-4 py-3">
        <p className="text-[10px] uppercase tracking-[0.22em] text-white/[0.34]">
          Shipping View
        </p>
        <h3 className="mt-1 text-[18px] text-white">Vessel Timeline</h3>
      </div>
      <div className="grid gap-4 p-4 xl:grid-cols-[0.9fr_1.1fr]">
        <div className="border border-white/8 bg-[rgba(255,255,255,0.02)] p-4">
          <div className="text-[10px] uppercase tracking-[0.18em] text-white/[0.3]">
            Current Leg
          </div>
          <div className="mt-3 space-y-3 text-[11px] text-white/[0.7]">
            <div>
              <div className="text-white/[0.34]">Vessel</div>
              <div className="mt-1 text-white">{primaryName ?? "--"}</div>
            </div>
            <div>
              <div className="text-white/[0.34]">Phase</div>
              <div className="mt-1 text-white">{phase}</div>
            </div>
            <div>
              <div className="text-white/[0.34]">Port Index</div>
              <div className="mt-1 text-white">
                {readStr(currentIdx || "--")}
              </div>
            </div>
            <div>
              <div className="text-white/[0.34]">Sigma (time advance)</div>
              <div className="mt-1 text-white">{sigma.toFixed(2)} d</div>
            </div>
          </div>
          {vesselNames.length > 1 ? (
            <div className="mt-4 border-t border-white/8 pt-3">
              <div className="text-[10px] uppercase tracking-[0.14em] text-white/[0.28]">
                All Vessels ({vesselNames.length})
              </div>
              <div className="mt-2 space-y-1">
                {vesselNames.slice(0, 6).map((name) => {
                  const vState = context.entityCache.getEntity(name);
                  return (
                    <div
                      key={name}
                      className="flex items-center justify-between text-[10px]"
                    >
                      <span className="text-white/[0.56]">{name}</span>
                      <span className="text-white/[0.36]">
                        {readStr(vState?._phase)}
                      </span>
                    </div>
                  );
                })}
                {vesselNames.length > 6 && (
                  <div className="text-[9px] text-white/[0.3]">
                    +{vesselNames.length - 6} more
                  </div>
                )}
              </div>
            </div>
          ) : null}
        </div>

        <div className="border border-white/8 bg-[rgba(255,255,255,0.02)] p-4">
          <div className="text-[10px] uppercase tracking-[0.18em] text-white/[0.3]">
            Schedule Projection
          </div>
          <div className="mt-4 space-y-0">
            {timeline.map((item, index) => (
              <div
                key={item.label}
                className="grid grid-cols-[18px_1fr_auto] items-center gap-3 border-b border-white/6 py-3 text-[11px] last:border-b-0"
              >
                <div
                  className={`h-2.5 w-2.5 rounded-full ${item.active ? "bg-[#9ad6dd]" : "bg-white/[0.16]"}`}
                />

                <div>
                  <div className="text-white">{item.label}</div>
                  <div className="mt-0.5 text-[10px] text-white/[0.36]">
                    Leg {index + 1}
                  </div>
                </div>
                <div className="font-mono text-white/[0.56]">{item.time} d</div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
