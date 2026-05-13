import type { ExtensionViewProps } from "../../types";

function readMetric(value: unknown): string {
  return value === null || value === undefined ? "--" : String(value);
}

function isPortEntity(name: string): boolean {
  return name.startsWith("Port_") || name.includes("_PT_");
}

function isVesselEntity(name: string): boolean {
  return (
    name.startsWith("Vessel_") ||
    /^AEU\d+-W\d+$/.test(name) ||
    name.includes("-W")
  );
}

export function PortKpiPanel({ context }: ExtensionViewProps) {
  const allNames = Array.from(context.entityCache.getAllEntities().keys());
  const portNames = allNames.filter(isPortEntity);
  const vesselNames = allNames.filter(isVesselEntity);

  // Aggregate port metrics
  const totalBuffer = portNames.reduce((sum, name) => {
    const state = context.entityCache.getEntity(name);
    return (
      sum +
      (typeof state?.cargo_buffer_ffe === "number" ? state.cargo_buffer_ffe : 0)
    );
  }, 0);
  const totalDischarged = portNames.reduce((sum, name) => {
    const state = context.entityCache.getEntity(name);
    return (
      sum +
      (typeof state?.cargo_discharged_ffe === "number"
        ? state.cargo_discharged_ffe
        : 0)
    );
  }, 0);

  return (
    <section className="border border-white/8 bg-[rgba(11,15,22,0.92)]">
      <div className="border-b border-white/8 px-3 py-2">
        <p className="text-[10px] uppercase tracking-[0.18em] text-white/[0.34]">
          Shipping KPI
        </p>
        <h3 className="mt-1 text-[14px] text-white">
          Port Operations Snapshot
        </h3>
      </div>
      <div className="grid gap-2 p-3 md:grid-cols-4">
        <div className="border border-white/8 bg-[rgba(255,255,255,0.02)] p-3">
          <div className="text-[10px] text-white/[0.36]">Ports</div>
          <div className="mt-1 text-[18px] text-white">{portNames.length}</div>
        </div>
        <div className="border border-white/8 bg-[rgba(255,255,255,0.02)] p-3">
          <div className="text-[10px] text-white/[0.36]">Active Vessels</div>
          <div className="mt-1 text-[18px] text-white">
            {vesselNames.length}
          </div>
        </div>
        <div className="border border-white/8 bg-[rgba(255,255,255,0.02)] p-3">
          <div className="text-[10px] text-white/[0.36]">
            Total Buffer (FFE)
          </div>
          <div className="mt-1 text-[18px] text-white">
            {totalBuffer > 0 ? totalBuffer.toFixed(0) : "--"}
          </div>
        </div>
        <div className="border border-white/8 bg-[rgba(255,255,255,0.02)] p-3">
          <div className="text-[10px] text-white/[0.36]">
            Total Discharged (FFE)
          </div>
          <div className="mt-1 text-[18px] text-white">
            {totalDischarged > 0 ? totalDischarged.toFixed(0) : "--"}
          </div>
        </div>
      </div>
      {portNames.length > 0 ? (
        <div className="border-t border-white/8 px-3 py-2">
          <div className="text-[9px] uppercase tracking-[0.14em] text-white/[0.28]">
            Per-Port Detail
          </div>
          <div className="mt-1.5 grid gap-1.5 md:grid-cols-2">
            {portNames.slice(0, 6).map((name) => {
              const state = context.entityCache.getEntity(name);
              const shortName = name
                .replace(/^[^_]+_PT_/, "")
                .replace(/^Port_/, "");
              return (
                <div
                  key={name}
                  className="flex items-center justify-between border border-white/6 bg-white/[0.02] px-2 py-1 text-[10px]"
                >
                  <span className="text-white/[0.56]">{shortName}</span>
                  <span className="text-white/[0.36]">
                    buf: {readMetric(state?.cargo_buffer_ffe)}
                  </span>
                </div>
              );
            })}
          </div>
        </div>
      ) : null}
    </section>
  );
}
