"use client";

import { useCallback, useMemo } from "react";
import {
  ReactFlow,
  Background,
  Controls,
  MiniMap,
  useNodesState,
  useEdgesState,
  type Node,
  type Edge,
  type NodeTypes,
  Position,
  MarkerType,
} from "@xyflow/react";
import dagre from "dagre";
import "@xyflow/react/dist/style.css";

// ============================================================
// Entity classification
// ============================================================

export type EntityKind = "demand" | "port" | "vessel" | "network" | "other";

const KIND_CONFIG: Record<EntityKind, { label: string; color: string }> = {
  demand: { label: "Demand", color: "#7c3aed" },
  port: { label: "Port", color: "#047857" },
  vessel: { label: "Vessel", color: "#b45309" },
  network: { label: "Network", color: "#0369a1" },
  other: { label: "Other", color: "#6b7280" },
};

export function classifyEntity(name: string): EntityKind {
  if (name.startsWith("Demand") || name.includes("_Demand")) return "demand";
  if (name.startsWith("Port_") || name.includes("_PT_")) return "port";
  if (
    name.startsWith("Vessel_") ||
    /^AEU\d+-W\d+$/.test(name) ||
    name.includes("-W")
  )
    return "vessel";
  if (name === "ShippingNetwork" || name.includes("Network")) return "network";
  return "other";
}

// ============================================================
// Connection inference
// ============================================================

export interface EntityConnection {
  source: string;
  sourcePort: string;
  target: string;
  targetPort: string;
}

export function inferConnections(entityNames: string[]): EntityConnection[] {
  const connections: EntityConnection[] = [];
  const demands = entityNames.filter((n) => classifyEntity(n) === "demand");
  const ports = entityNames.filter((n) => classifyEntity(n) === "port");
  const vessels = entityNames.filter((n) => classifyEntity(n) === "vessel");
  const networks = entityNames.filter((n) => classifyEntity(n) === "network");

  for (const demand of demands) {
    for (const port of ports) {
      connections.push({
        source: demand,
        sourcePort: "o_demand",
        target: port,
        targetPort: "i_cargo_in",
      });
    }
  }

  for (const vessel of vessels) {
    for (const port of ports) {
      connections.push({
        source: vessel,
        sourcePort: "o_arrival",
        target: port,
        targetPort: "i_arrival",
      });
      connections.push({
        source: vessel,
        sourcePort: "o_departure",
        target: port,
        targetPort: "i_departure",
      });
      connections.push({
        source: vessel,
        sourcePort: "o_cargo_discharge",
        target: port,
        targetPort: "i_cargo_discharge",
      });
    }
  }

  for (const port of ports) {
    for (const vessel of vessels) {
      connections.push({
        source: port,
        sourcePort: "o_cargo_out",
        target: vessel,
        targetPort: "i_cargo",
      });
    }
  }

  for (const port of ports) {
    for (const network of networks) {
      connections.push({
        source: port,
        sourcePort: "o_stats",
        target: network,
        targetPort: "i_port_feedback",
      });
    }
  }

  return connections;
}

// ============================================================
// Dagre auto-layout
// ============================================================

const NODE_WIDTH = 220;
const NODE_HEIGHT = 80;

function layoutWithDagre(nodes: Node[], edges: Edge[]): Node[] {
  const g = new dagre.graphlib.Graph();
  g.setDefaultEdgeLabel(() => ({}));
  g.setGraph({ rankdir: "LR", nodesep: 50, ranksep: 120 });

  for (const node of nodes) {
    g.setNode(node.id, { width: NODE_WIDTH, height: NODE_HEIGHT });
  }
  for (const edge of edges) {
    g.setEdge(edge.source, edge.target);
  }

  dagre.layout(g);

  return nodes.map((node) => {
    const pos = g.node(node.id);
    return {
      ...node,
      position: { x: pos.x - NODE_WIDTH / 2, y: pos.y - NODE_HEIGHT / 2 },
    };
  });
}

// ============================================================
// Custom Node Component
// ============================================================

function formatFieldValue(value: unknown): string {
  if (typeof value === "number")
    return Number.isInteger(value) ? String(value) : value.toFixed(2);
  if (typeof value === "string")
    return value.length > 12 ? value.slice(0, 12) + "..." : value;
  if (typeof value === "boolean") return value ? "true" : "false";
  if (value === null || value === undefined) return "--";
  return String(value);
}

function ShippingNode({
  data,
  selected,
}: {
  data: Node["data"];
  selected: boolean;
}) {
  const kind: EntityKind = data.kind ?? "other";
  const config = KIND_CONFIG[kind];
  const runtime = data.runtime as Record<string, unknown> | undefined;

  const displayFields = runtime
    ? Object.entries(runtime)
        .filter(([k]) => !k.startsWith("_") || k === "_phase" || k === "_sigma")
        .slice(0, 3)
    : [];

  return (
    <div
      className={
        "min-w-[180px] rounded-md border bg-[rgba(18,22,31,0.95)] backdrop-blur-sm transition-shadow " +
        (selected
          ? "shadow-[0_0_0_2px_rgba(143,194,198,0.5)]"
          : "shadow-[var(--shadow-sm)]")
      }
      style={{
        borderColor: selected ? "rgba(143,194,198,0.5)" : "var(--border-color)",
      }}
    >
      <div
        className="flex items-center gap-1.5 rounded-t-md border-b px-2.5 py-1.5"
        style={{
          borderColor: "var(--border-color)",
          background: config.color + "18",
        }}
      >
        <span
          className="h-2 w-2 rounded-full"
          style={{ background: config.color }}
        />

        <span
          className="text-[10px] uppercase tracking-[0.12em]"
          style={{ color: config.color }}
        >
          {config.label}
        </span>
        {data.portCount ? (
          <span className="ml-auto text-[9px] text-white/[0.3]">
            {String(data.portCount)}p
          </span>
        ) : null}
      </div>

      <div className="px-2.5 py-2">
        <div className="truncate text-[11px] font-medium text-white">
          {String(data.label)}
        </div>
        {displayFields.length > 0 ? (
          <div className="mt-1.5 flex flex-wrap gap-1">
            {displayFields.map(([key, value]) => (
              <span
                key={key}
                className="border border-white/8 px-1 py-0.5 text-[9px] text-white/[0.52]"
              >
                {key.replace(/^_/, "")}: {formatFieldValue(value)}
              </span>
            ))}
          </div>
        ) : null}
      </div>

      <div className="flex items-center justify-between border-t border-white/6 px-2 py-1">
        <div className="flex gap-0.5">
          {((data.inPorts as string[]) ?? []).slice(0, 3).map((p) => (
            <span
              key={p}
              className="h-1.5 w-1.5 rounded-full bg-[#047857]"
              title={p}
            />
          ))}
        </div>
        <div className="flex gap-0.5">
          {((data.outPorts as string[]) ?? []).slice(0, 3).map((p) => (
            <span
              key={p}
              className="h-1.5 w-1.5 rounded-full bg-[#b45309]"
              title={p}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

const nodeTypes: NodeTypes = {
  shipping: ShippingNode,
};

// ============================================================
// Main Canvas Component
// ============================================================

import type { EntityInfo } from "@/protocol/types";

export interface ShippingCanvasProps {
  entities: EntityInfo[];
  runtimeEntities: Array<[string, Record<string, unknown>]>;
  selectedEntityName: string | null;
  selectedRuntimeEntityName: string | null;
  onSelectEntity: (name: string) => void;
}

export function ShippingCanvas({
  entities,
  runtimeEntities,
  onSelectEntity,
}: ShippingCanvasProps) {
  const entityNames = useMemo(() => entities.map((e) => e.name), [entities]);
  const connections = useMemo(
    () => inferConnections(entityNames),
    [entityNames],
  );

  const initialNodes = useMemo(() => {
    const runtimeMap = new Map(runtimeEntities);
    return entities.map((entity) => {
      const kind = classifyEntity(entity.name);
      const config = KIND_CONFIG[kind];
      const runtime = runtimeMap.get(entity.name) as
        | Record<string, unknown>
        | undefined;
      const inPorts = [
        ...new Set(
          connections
            .filter((c) => c.target === entity.name)
            .map((c) => c.targetPort),
        ),
      ];

      const outPorts = [
        ...new Set(
          connections
            .filter((c) => c.source === entity.name)
            .map((c) => c.sourcePort),
        ),
      ];

      return {
        id: entity.name,
        type: "shipping",
        position: { x: 0, y: 0 },
        data: {
          label: entity.name,
          kind,
          color: config.color,
          portCount: entity.port_count,
          inPorts,
          outPorts,
          runtime: runtime ?? undefined,
        },
        sourcePosition: Position.Right,
        targetPosition: Position.Left,
      } as Node;
    });
  }, [entities, runtimeEntities, connections]);

  const initialEdges = useMemo(() => {
    const edgeMap = new Map<
      string,
      { source: string; target: string; labels: string[] }
    >();
    for (const conn of connections) {
      const key = conn.source + "->" + conn.target;
      const existing = edgeMap.get(key);
      if (existing) {
        existing.labels.push(conn.sourcePort);
      } else {
        edgeMap.set(key, {
          source: conn.source,
          target: conn.target,
          labels: [conn.sourcePort],
        });
      }
    }

    return Array.from(edgeMap.entries()).map(([key, val]) => {
      const sourceKind = classifyEntity(val.source);
      const config = KIND_CONFIG[sourceKind];
      return {
        id: key,
        source: val.source,
        target: val.target,
        type: "smoothstep" as const,
        animated: sourceKind === "demand",
        label:
          val.labels.length <= 2
            ? val.labels.join(", ")
            : val.labels.length + " ports",
        labelStyle: {
          fill: "rgba(255,255,255,0.36)",
          fontSize: 9,
          fontFamily: "inherit",
        },
        labelBgStyle: { fill: "rgba(18,22,31,0.9)", stroke: "none" },
        style: { stroke: config.color, strokeWidth: 1.5, opacity: 0.6 },
        markerEnd: {
          type: MarkerType.ArrowClosed,
          width: 12,
          height: 12,
          color: config.color,
        },
        interactionWidth: 10,
      } as Edge;
    });
  }, [connections]);

  const layoutedNodes = useMemo(
    () => layoutWithDagre(initialNodes, initialEdges),
    [initialNodes, initialEdges],
  );

  const [nodes, setNodes, onNodesChange] = useNodesState(layoutedNodes);
  const [edges, setEdges, onEdgesChange] = useEdgesState(initialEdges);

  useMemo(() => {
    setNodes(layoutedNodes);
    setEdges(initialEdges);
  }, [layoutedNodes, initialEdges, setNodes, setEdges]);

  const onNodeClick = useCallback(
    (_event: React.MouseEvent, node: Node) => {
      onSelectEntity(node.id);
    },
    [onSelectEntity],
  );

  const minimapNodeColor = useCallback((node: Node) => {
    const kind = (node.data?.kind as EntityKind) ?? "other";
    return KIND_CONFIG[kind].color;
  }, []);

  if (entities.length === 0) {
    return (
      <div className="flex h-full w-full min-h-0 flex-col bg-[rgba(10,13,19,0.96)]">
        <div className="flex items-center justify-between border-b border-white/8 px-3 py-2">
          <div>
            <div className="text-[10px] uppercase tracking-[0.18em] text-white/[0.34]">
              Composer
            </div>
            <div className="mt-0.5 text-[14px] text-white">Shipping Canvas</div>
          </div>
        </div>
        <div className="flex flex-1 items-center justify-center p-6">
          <div
            className="rounded-md border border-dashed p-4"
            style={{
              borderColor: "var(--border-color)",
              background: "var(--panel-subtle)",
            }}
          >
            <div className="text-[11px] text-white">Canvas pending</div>
            <p className="mt-1 text-[10px] leading-5 text-white/[0.5]">
              Connect runtime and load a shipping preset to see the model
              topology.
            </p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="flex h-full w-full min-h-0 flex-col bg-[rgba(10,13,19,0.96)]">
      <div className="flex items-center justify-between border-b border-white/8 px-3 py-2">
        <div>
          <div className="text-[10px] uppercase tracking-[0.18em] text-white/[0.34]">
            Composer
          </div>
          <div className="mt-0.5 text-[14px] text-white">Shipping Canvas</div>
        </div>
        <div className="flex items-center gap-1.5">
          <span className="rounded-[6px] border border-[var(--border-color)] px-1.5 py-0.5 text-[9px] uppercase tracking-[0.1em] text-[var(--text-secondary)]">
            {entities.length} components
          </span>
          <span className="rounded-[6px] border border-[var(--border-color)] px-1.5 py-0.5 text-[9px] uppercase tracking-[0.1em] text-[var(--text-secondary)]">
            {runtimeEntities.length} live
          </span>
          <span className="rounded-[6px] border border-[var(--border-color)] px-1.5 py-0.5 text-[9px] uppercase tracking-[0.1em] text-[var(--text-secondary)]">
            {connections.length} connections
          </span>
        </div>
      </div>
      <div className="flex-1">
        <ReactFlow
          nodes={nodes}
          edges={edges}
          onNodesChange={onNodesChange}
          onEdgesChange={onEdgesChange}
          onNodeClick={onNodeClick}
          nodeTypes={nodeTypes}
          fitView
          fitViewOptions={{ padding: 0.3 }}
          proOptions={{ hideAttribution: true }}
          style={{ background: "transparent" }}
          defaultEdgeOptions={{ type: "smoothstep" }}
        >
          <Background color="rgba(255,255,255,0.04)" gap={24} size={1} />

          <Controls
            showInteractive={false}
            style={{
              background: "var(--panel-bg)",
              borderColor: "var(--border-color)",
              borderRadius: 6,
            }}
          />

          <MiniMap
            nodeColor={minimapNodeColor}
            maskColor="rgba(10,13,19,0.8)"
            style={{
              background: "var(--panel-bg)",
              borderColor: "var(--border-color)",
              borderRadius: 6,
            }}
          />
        </ReactFlow>
      </div>
    </div>
  );
}
