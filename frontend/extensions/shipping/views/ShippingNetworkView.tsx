import type { ExtensionViewProps } from "../../types";

function readNumber(value: unknown): string {
  return typeof value === "number" ? String(value) : "--";
}

/** Classify entity names by semantic kind */
function classifyEntities(entityNames: string[]) {
  const networks: string[] = [];
  const vessels: string[] = [];
  const ports: string[] = [];
  const demands: string[] = [];

  for (const name of entityNames) {
    if (name === "ShippingNetwork" || name.includes("Network"))
      networks.push(name);
    else if (
      name.startsWith("Vessel_") ||
      /^AEU\d+-W\d+$/.test(name) ||
      name.includes("-W")
    )
      vessels.push(name);
    else if (name.startsWith("Port_") || name.includes("_PT_"))
      ports.push(name);
    else if (name.startsWith("Demand") || name.includes("_Demand"))
      demands.push(name);
  }

  return { networks, vessels, ports, demands };
}

/** Pick the most relevant display fields from an entity state */
function pickDisplayFields(
  state: Record<string, unknown>,
  maxFields = 3,
): Array<[string, string]> {
  const skip = new Set([
    "_inbox",
    "_outbox",
    "loaded_cargo",
    "cargo_buffer",
    "discharged_cargo",
    "arrivals",
    "departures",
    "_pending_out_cargo",
    "route_port_codes",
  ]);
  const entries = Object.entries(state).filter(([k]) => !skip.has(k));
  return entries
    .slice(0, maxFields)
    .map(([k, v]) => [
      k,
      typeof v === "number"
        ? Number.isInteger(v)
          ? String(v)
          : v.toFixed(2)
        : String(v ?? "--"),
    ]);
}

export function ShippingNetworkView({ context }: ExtensionViewProps) {
  const allNames = Array.from(context.entityCache.getAllEntities().keys());
  const { networks, vessels, ports, demands } = classifyEntities(allNames);

  const networkEntity =
    networks.length > 0 ? context.entityCache.getEntity(networks[0]) : null;
  const vesselEntities = vessels.map((name) => ({
    name,
    state: context.entityCache.getEntity(name),
  }));
  const portEntities = ports.map((name) => ({
    name,
    state: context.entityCache.getEntity(name),
  }));
  const demandEntities = demands.map((name) => ({
    name,
    state: context.entityCache.getEntity(name),
  }));

  const cards = [
    {
      title: "Demand",
      color: "#7c3aed",
      items:
        demandEntities.length > 0
          ? demandEntities
              .slice(0, 3)
              .map((d) => [
                d.name,
                readNumber(d.state?.weekly_ffe ?? d.state?._sigma),
              ])
          : [["No demand entities", "--"] as const],
    },
    {
      title: "Ports",
      color: "#047857",
      items:
        portEntities.length > 0
          ? portEntities
              .slice(0, 3)
              .map((p) => [
                p.name,
                readNumber(p.state?.cargo_buffer_ffe ?? p.state?._phase),
              ])
          : [["No port entities", "--"] as const],
    },
    {
      title: "Vessels",
      color: "#b45309",
      items:
        vesselEntities.length > 0
          ? vesselEntities
              .slice(0, 3)
              .map((v) => [
                v.name,
                String(v.state?.current_port ?? v.state?._phase ?? "--"),
              ])
          : [["No vessel entities", "--"] as const],
    },
    {
      title: "Network",
      color: "#0369a1",
      items: networkEntity
        ? Object.entries(networkEntity)
            .filter(([k]) => !k.startsWith("_"))
            .slice(0, 3)
            .map(([k, v]) => [k, readNumber(v)])
        : [["No network entity", "--"] as const],
    },
  ];

  return (
    <section className="border border-white/8 bg-[rgba(11,15,22,0.92)]">
      <div className="flex items-center justify-between border-b border-white/8 px-4 py-3">
        <div>
          <p className="text-[10px] uppercase tracking-[0.22em] text-white/[0.34]">
            Shipping View
          </p>
          <h3 className="mt-1 text-[18px] text-white">Route Network</h3>
        </div>
        <div className="flex items-center gap-2">
          <span className="border border-white/8 px-2 py-1 text-[10px] text-white/[0.6]">
            {context.modelEntities?.entity_count ??
              context.entityCache.entityCount}{" "}
            entities
          </span>
        </div>
      </div>

      <div className="grid gap-4 p-4 xl:grid-cols-[1.05fr_0.95fr]">
        <div className="border border-white/8 bg-[rgba(255,255,255,0.02)] p-4">
          <div className="mb-3 text-[10px] uppercase tracking-[0.18em] text-white/[0.3]">
            Flow Topology
          </div>
          <div className="grid gap-3 md:grid-cols-4">
            {cards.map((card) => (
              <div
                key={card.title}
                className="border border-white/8 bg-[rgba(18,23,31,0.88)] p-3"
              >
                <div className="flex items-center gap-1.5">
                  <span
                    className="h-2 w-2 rounded-full"
                    style={{ background: card.color }}
                  />

                  <span className="text-[11px] text-white">{card.title}</span>
                  <span className="ml-auto text-[9px] text-white/[0.34]">
                    {card.items.length}
                  </span>
                </div>
                <div className="mt-3 space-y-2">
                  {card.items.map((item, idx) => (
                    <div key={idx} className="text-[10px]">
                      <div className="truncate text-white/[0.34]">
                        {Array.isArray(item) ? item[0] : String(item)}
                      </div>
                      <div className="mt-0.5 text-white/[0.82]">
                        {Array.isArray(item) ? item[1] : "--"}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>

          <div className="mt-4 border border-white/8 bg-[rgba(255,255,255,0.02)] p-3">
            <div className="text-[10px] uppercase tracking-[0.16em] text-white/[0.3]">
              Connection Narrative
            </div>
            <div className="mt-2 space-y-2 text-[11px] leading-6 text-white/[0.58]">
              {demands.length > 0 && ports.length > 0 && vessels.length > 0 ? (
                <div>
                  {demands.slice(0, 2).join(", ")} &rarr;{" "}
                  {ports.slice(0, 3).join(", ")} &rarr;{" "}
                  {vessels.slice(0, 3).join(", ")} &rarr;{" "}
                  {networks[0] ?? "Network"}
                </div>
              ) : (
                <div>
                  Connect runtime and load a shipping preset to see the flow
                  topology.
                </div>
              )}
            </div>
          </div>
        </div>

        <div className="border border-white/8 bg-[rgba(255,255,255,0.02)] p-4">
          <div className="text-[10px] uppercase tracking-[0.18em] text-white/[0.3]">
            Live Snapshot
          </div>
          <div className="mt-3 space-y-2">
            <div className="border border-white/8 bg-[rgba(18,23,31,0.88)] p-3 text-[11px] text-white/[0.7]">
              <div className="text-white">Ports</div>
              <div className="mt-1 text-[18px] text-white">{ports.length}</div>
            </div>
            <div className="border border-white/8 bg-[rgba(18,23,31,0.88)] p-3 text-[11px] text-white/[0.7]">
              <div className="text-white">Vessels</div>
              <div className="mt-1 text-[18px] text-white">
                {vessels.length}
              </div>
            </div>
            <div className="border border-white/8 bg-[rgba(18,23,31,0.88)] p-3 text-[11px] text-white/[0.7]">
              <div className="text-white">Current Time</div>
              <div className="mt-1 text-[18px] text-white">
                {context.runner.currentTime.toFixed(2)} d
              </div>
            </div>
            {networkEntity ? (
              <div className="border border-white/8 bg-[rgba(18,23,31,0.88)] p-3 text-[11px] text-white/[0.7]">
                <div className="text-white">Network Phase</div>
                <div className="mt-1 text-[14px] text-white">
                  {String(networkEntity._phase ?? "--")}
                </div>
              </div>
            ) : null}
          </div>
        </div>
      </div>
    </section>
  );
}
