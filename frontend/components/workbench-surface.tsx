"use client";

import { useMemo, useState, type ReactNode } from "react";
import { EmptyBlock, Tag } from "@/components/workbench-support";
import { formatValue, sanitizeIdentifier } from "@/components/workbench-utils";
import type {
  ExtensionRuntimeContext,
  ExtensionViewDefinition,
} from "@/extensions/types";
import type {
  ShippingProjectFile,
  ShippingProjectScenario,
} from "@/lib/shipping-project";
import { ShippingCanvas } from "@/components/canvas/shippingcanvas";
import type { EntityInfo } from "@/protocol/types";

export type WorkbenchPageKind = "canvas" | "code" | "document" | "extension";

export interface WorkbenchPage {
  id: string;
  kind: WorkbenchPageKind;
  title: string;
  subtitle?: string;
  fileId?: string;
  viewId?: string;
}

function buildDslPreview(
  modelName: string | undefined,
  entities: Array<{
    name: string;
    parameters: Array<{ name: string; type: string }>;
  }>,
  getParameterDraft: (
    entityName: string,
    parameterName: string,
    fallbackType: string,
  ) => string,
  selectedEntityName: string | null,
) {
  const name = sanitizeIdentifier(modelName ?? "ShippingWorkbench");
  const componentBlock =
    entities.length > 0
      ? entities
          .map((entity) => {
            const params =
              entity.parameters.length > 0
                ? entity.parameters
                    .map(
                      (parameter) =>
                        `    ${parameter.name} = ${getParameterDraft(entity.name, parameter.name, parameter.type)}`,
                    )
                    .join("\n")
                : "    # parameters pending parser projection";
            const marker =
              selectedEntityName === entity.name
                ? "    # focus: selected in workbench\n"
                : "";
            return `component ${sanitizeIdentifier(entity.name)} begin\n${marker}${params}\nend`;
          })
          .join("\n\n")
      : `component Vessel_Surabaya begin\n    capacity_ffe = 480\n    start_delay = 0.0\n    route_id = "AEU3"\nend`;

  return `model ${name} begin
${componentBlock}

compose begin
    connect DemandGenerator_AsiaLoop.o_demand => Port_Shanghai.i_cargo_in
    connect Port_Shanghai.o_cargo_out => Vessel_Surabaya.i_cargo
    connect Vessel_Surabaya.o_arrival => Port_Singapore.i_arrival
    connect Port_Singapore.o_release => ShippingNetwork.i_port_feedback
end
end`;
}

function renderDocument(file: ShippingProjectFile) {
  return (
    <div className="h-full overflow-auto bg-[#11151c]">
      <div className="flex items-center justify-between border-b border-white/8 bg-[rgba(255,255,255,0.02)] px-3 py-1.5 text-[10px] text-white/[0.44]">
        <div className="flex items-center gap-2">
          <span className="bg-white/[0.05] px-1.5 py-0.5">{file.label}</span>
          <span>{file.language}</span>
        </div>
        <span>{file.path}</span>
      </div>
      <pre className="min-h-full whitespace-pre-wrap px-4 py-3 font-mono text-[11px] leading-6 text-[#d7e0ea]">
        {file.content}
      </pre>
    </div>
  );
}

function CanvasStudio({
  entities,
  runtimeEntities,
  selectedEntityName,
  selectedRuntimeEntityName,
  onSelectEntity,
}: {
  entities: Array<{
    name: string;
    parameter_count: number;
    port_count: number;
  }>;
  runtimeEntities: Array<[string, Record<string, unknown>]>;
  selectedEntityName: string | null;
  selectedRuntimeEntityName: string | null;
  onSelectEntity: (name: string) => void;
}) {
  const lanes = [
    {
      id: "demand",
      label: "Demand",
      match: (name: string) => name.startsWith("Demand"),
    },
    {
      id: "port",
      label: "Ports",
      match: (name: string) => name.startsWith("Port_"),
    },
    {
      id: "vessel",
      label: "Vessels",
      match: (name: string) => name.startsWith("Vessel_"),
    },
    {
      id: "network",
      label: "Network",
      match: (name: string) => name === "ShippingNetwork",
    },
  ];

  const grouped = lanes.map((lane) => ({
    ...lane,
    items: entities.filter((entity) => lane.match(entity.name)),
  }));

  return (
    <div className="flex h-full min-h-0 flex-col bg-[rgba(10,13,19,0.96)]">
      <div className="flex items-center justify-between border-b border-white/8 px-3 py-2">
        <div>
          <div className="text-[10px] uppercase tracking-[0.18em] text-white/[0.34]">
            Composer
          </div>
          <div className="mt-0.5 text-[14px] text-white">Shipping Canvas</div>
        </div>
        <div className="flex items-center gap-1.5">
          <Tag>{entities.length} components</Tag>
          <Tag>{runtimeEntities.length} live</Tag>
        </div>
      </div>
      <div className="min-h-0 flex-1 overflow-auto p-3">
        {entities.length === 0 ? (
          <EmptyBlock
            title="Canvas pending"
            description="连接模型结构后，这里会显示海运模型的组件组织与连接关系。"
          />
        ) : (
          <div
            className="grid min-w-[960px] gap-3"
            style={{
              gridTemplateColumns: `repeat(${grouped.length}, minmax(0, 1fr))`,
            }}
          >
            {grouped.map((lane) => (
              <section
                key={lane.id}
                className="border border-white/8 bg-[rgba(255,255,255,0.02)]"
              >
                <div className="border-b border-white/8 px-3 py-2 text-[10px] uppercase tracking-[0.16em] text-white/[0.32]">
                  {lane.label}
                </div>
                <div className="space-y-2 p-2">
                  {lane.items.map((entity) => {
                    const runtime = runtimeEntities.find(
                      ([name]) => name === entity.name,
                    )?.[1];
                    const active =
                      selectedEntityName === entity.name ||
                      selectedRuntimeEntityName === entity.name;
                    return (
                      <button
                        key={entity.name}
                        onClick={() => onSelectEntity(entity.name)}
                        className={`w-full border px-2 py-2 text-left transition ${
                          active
                            ? "border-[rgba(143,194,198,0.35)] bg-[rgba(143,194,198,0.08)]"
                            : "border-white/8 bg-[rgba(18,22,31,0.92)] hover:border-white/[0.14] hover:bg-[rgba(24,28,38,0.96)]"
                        }`}
                      >
                        <div className="flex items-center justify-between gap-2">
                          <span className="truncate text-[11px] text-white">
                            {entity.name}
                          </span>
                          <span className="text-[9px] text-white/[0.34]">
                            {entity.parameter_count}p
                          </span>
                        </div>
                        <div className="mt-1 text-[9px] text-white/[0.4]">
                          {entity.port_count} ports
                        </div>
                        {runtime ? (
                          <div className="mt-2 flex flex-wrap gap-1 text-[9px]">
                            {Object.entries(runtime)
                              .slice(0, 3)
                              .map(([key, value]) => (
                                <span
                                  key={key}
                                  className="border border-white/8 px-1 py-0.5 text-white/[0.52]"
                                >
                                  {key}: {formatValue(value)}
                                </span>
                              ))}
                          </div>
                        ) : null}
                      </button>
                    );
                  })}
                </div>
              </section>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function CodeStudio({
  modelName,
  modelEntities,
  getParameterDraft,
  selectedEntityName,
  activeScenario,
  error,
}: {
  modelName?: string;
  modelEntities: EntityInfo[];
  getParameterDraft: (
    entityName: string,
    parameterName: string,
    fallbackType: string,
  ) => string;
  selectedEntityName: string | null;
  activeScenario: ShippingProjectScenario | null;
  error: string | null;
}) {
  const code = buildDslPreview(
    modelName,
    modelEntities,
    getParameterDraft,
    selectedEntityName,
  );
  const codeLines = code.split("\n");

  return (
    <div className="grid h-full w-full min-h-0 lg:grid-cols-[minmax(0,1fr)_280px]">
      <div className="min-h-0 overflow-hidden bg-[#11151c]">
        <div className="flex items-center justify-between border-b border-white/8 bg-[rgba(255,255,255,0.02)] px-3 py-1.5 text-[10px] text-white/[0.44]">
          <div className="flex items-center gap-2">
            <span className="bg-white/[0.05] px-1.5 py-0.5">
              shipping-model.anydsl
            </span>
            <span>{activeScenario?.label ?? "default scenario"}</span>
          </div>
          <span>{modelName ?? "ShippingModel"}</span>
        </div>
        <div className="grid h-full min-h-0 grid-cols-[44px_1fr] overflow-auto">
          <div className="border-r border-white/8 bg-[rgba(255,255,255,0.015)] px-1.5 py-2 text-right font-mono text-[10px] leading-5 text-white/[0.22]">
            {codeLines.map((_, index) => (
              <div key={index}>{index + 1}</div>
            ))}
          </div>
          <pre className="px-3 py-2 font-mono text-[11px] leading-5 text-[#d7e0ea]">
            {code}
          </pre>
        </div>
      </div>
      <div className="min-h-0 overflow-auto border-l border-white/8 bg-[rgba(8,12,18,0.96)] p-2">
        <div className="text-[10px] uppercase tracking-[0.18em] text-white/[0.34]">
          Code Lens
        </div>
        <div className="mt-2 space-y-2">
          <div className="border border-white/8 bg-white/[0.03] p-2 text-[11px] leading-5 text-white/[0.58]">
            这里显示的是以项目、属性面板和运行结构共同投影出来的 DSL 草图，保持
            Code 作为唯一真相。
          </div>
          {selectedEntityName ? (
            <div className="border border-[rgba(143,194,198,0.24)] bg-[rgba(143,194,198,0.08)] p-2 text-[11px] leading-5 text-[#cfe6e8]">
              当前焦点组件：{selectedEntityName}
            </div>
          ) : null}
          {error ? (
            <div className="border border-[rgba(202,113,61,0.35)] bg-[rgba(202,113,61,0.08)] p-2 text-[11px] leading-5 text-white/[0.76]">
              {error}
            </div>
          ) : null}
          {activeScenario ? (
            <div className="border border-white/8 bg-white/[0.03] p-2 text-[11px] leading-5 text-white/[0.58]">
              场景配置来源：{activeScenario.configPath}
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}

function WelcomeWorkbench({
  onConnect,
  projectLabel,
}: {
  onConnect: () => void;
  projectLabel: string;
}) {
  return (
    <div className="flex h-full w-full items-center justify-center p-5">
      <div className="grid w-full max-w-5xl gap-4 xl:grid-cols-[1.2fr_0.8fr]">
        <section className="border border-white/8 bg-[rgba(11,15,22,0.92)] p-6">
          <div className="text-[10px] uppercase tracking-[0.18em] text-white/[0.32]">
            Workbench
          </div>
          <h2 className="mt-3 text-[30px] leading-[1.08] text-white">
            用 IDE 的方式组织 {projectLabel} 的建模、运行和分析。
          </h2>
          <p className="mt-3 max-w-2xl text-[14px] leading-7 text-white/[0.56]">
            左侧是项目树和仿真树，中间是代码、画布、shipping
            专题页面，右侧是参数与运行时属性，底部保留事件、日志和 KPI 输出。
          </p>
          <div className="mt-5 flex flex-wrap gap-2">
            <button onClick={onConnect} className="btn-primary">
              连接运行时
            </button>
            <button onClick={onConnect} className="btn-ghost">
              进入 mock shipping runtime
            </button>
          </div>
        </section>
        <section className="space-y-3">
          <WorkbenchSummary
            title="Code"
            text="项目包、场景配置和组件参数都落在同一套代码与配置真相上。"
          />

          <WorkbenchSummary
            title="Canvas"
            text="把 demand、port、vessel、network 结构组织成可读、可选中的建模面。"
          />

          <WorkbenchSummary
            title="Views"
            text="shipping extension 的 network、timeline、scorecard 和 KPI 面板都作为页面或输出页接入。"
          />
        </section>
      </div>
    </div>
  );
}

function WorkbenchSummary({ title, text }: { title: string; text: string }) {
  return (
    <div className="border border-white/8 bg-[rgba(10,15,22,0.72)] p-4">
      <div className="text-[11px] uppercase tracking-[0.16em] text-white/[0.34]">
        {title}
      </div>
      <div className="mt-2 text-[13px] leading-6 text-white/[0.58]">{text}</div>
    </div>
  );
}

function ExtensionViewHost({
  view,
  context,
}: {
  view: ExtensionViewDefinition;
  context: ExtensionRuntimeContext | null;
}) {
  if (!context) {
    return (
      <div className="flex h-full items-center justify-center bg-[rgba(10,13,19,0.96)] p-6">
        <EmptyBlock
          title="View pending"
          description="连接运行时并加载 shipping preset 后，这里会显示领域专题页面。"
        />
      </div>
    );
  }

  return (
    <div className="h-full overflow-auto bg-[rgba(10,13,19,0.96)] p-3">
      <view.Component context={context} />
    </div>
  );
}

interface WorkbenchSurfaceProps {
  modelName?: string;
  modelEntities: EntityInfo[];
  runtimeEntities: Array<[string, Record<string, unknown>]>;
  getParameterDraft: (
    entityName: string,
    parameterName: string,
    fallbackType: string,
  ) => string;
  selectedEntity: EntityInfo | null;
  selectedRuntimeEntity: [string, Record<string, unknown>] | null;
  onSelectEntity: (name: string) => void;
  connected: boolean;
  error: string | null;
  onConnect: () => void;
  pages: WorkbenchPage[];
  activePageId: string | null;
  onSelectPage: (pageId: string) => void;
  onClosePage: (pageId: string) => void;
  files: ShippingProjectFile[];
  activeScenario: ShippingProjectScenario | null;
  extensionViews: ExtensionViewDefinition[];
  extensionContext: ExtensionRuntimeContext | null;
  projectLabel: string;
}

export function WorkbenchSurface({
  modelName,
  modelEntities,
  runtimeEntities,
  getParameterDraft,
  selectedEntity,
  selectedRuntimeEntity,
  onSelectEntity,
  connected,
  error,
  onConnect,
  pages,
  activePageId,
  onSelectPage,
  onClosePage,
  files,
  activeScenario,
  extensionViews,
  extensionContext,
  projectLabel,
}: WorkbenchSurfaceProps) {
  const activePage = useMemo(
    () => pages.find((page) => page.id === activePageId) ?? pages[0] ?? null,
    [pages, activePageId],
  );
  const [hoverPageId, setHoverPageId] = useState<string | null>(null);

  const renderPage = (): ReactNode => {
    if (!activePage) {
      return (
        <WelcomeWorkbench onConnect={onConnect} projectLabel={projectLabel} />
      );
    }

    if (activePage.kind === "canvas") {
      return (
        <ShippingCanvas
          entities={modelEntities}
          runtimeEntities={runtimeEntities}
          selectedEntityName={selectedEntity?.name ?? null}
          selectedRuntimeEntityName={selectedRuntimeEntity?.[0] ?? null}
          onSelectEntity={onSelectEntity}
        />
      );
    }

    if (activePage.kind === "code") {
      return (
        <CodeStudio
          modelName={modelName}
          modelEntities={modelEntities}
          getParameterDraft={getParameterDraft}
          selectedEntityName={selectedEntity?.name ?? null}
          activeScenario={activeScenario}
          error={error}
        />
      );
    }

    if (activePage.kind === "document" && activePage.fileId) {
      const file = files.find((entry) => entry.id === activePage.fileId);
      return file ? (
        renderDocument(file)
      ) : (
        <EmptyBlock title="File missing" description="对应项目文件未找到。" />
      );
    }

    if (activePage.kind === "extension" && activePage.viewId) {
      const view = extensionViews.find(
        (entry) => entry.id === activePage.viewId,
      );
      return view ? (
        <ExtensionViewHost view={view} context={extensionContext} />
      ) : (
        <EmptyBlock title="View missing" description="对应扩展视图未注册。" />
      );
    }

    return (
      <EmptyBlock title="Page unavailable" description="当前页面暂时不可用。" />
    );
  };

  if (!connected && pages.length === 0) {
    return (
      <WelcomeWorkbench onConnect={onConnect} projectLabel={projectLabel} />
    );
  }

  return (
    <div className="flex h-full w-full min-h-0 flex-col bg-[var(--workspace-bg)]">
      <div className="flex h-7 items-center overflow-x-auto border-b border-white/8 bg-[rgba(15,18,25,0.96)]">
        {pages.map((page) => {
          const active = page.id === activePage?.id;
          const closable = page.kind !== "canvas" && page.kind !== "code";
          return (
            <button
              key={page.id}
              onClick={() => onSelectPage(page.id)}
              onMouseEnter={() => setHoverPageId(page.id)}
              onMouseLeave={() =>
                setHoverPageId((current) =>
                  current === page.id ? null : current,
                )
              }
              className={`group flex items-center gap-1.5 border-r border-white/8 px-2.5 py-0.5 text-[10px] transition ${
                active
                  ? "bg-[rgba(255,255,255,0.06)] text-white"
                  : "bg-transparent text-white/[0.48] hover:bg-white/[0.03] hover:text-white"
              }`}
            >
              <span className="truncate">{page.title}</span>
              {closable ? (
                <span
                  onClick={(event) => {
                    event.stopPropagation();
                    onClosePage(page.id);
                  }}
                  className={`shrink-0 text-[10px] text-white/[0.4] ${hoverPageId === page.id || active ? "opacity-100" : "opacity-0 group-hover:opacity-100"}`}
                >
                  ×
                </span>
              ) : null}
            </button>
          );
        })}
      </div>
      <div className="min-h-0 flex-1">{renderPage()}</div>
    </div>
  );
}
