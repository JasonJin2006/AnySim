"use client";

import type { ComponentType, ReactNode } from "react";
import type { SimMode } from "@/hooks/useSimulation";
import { formatValue } from "@/components/workbench-utils";
import type { ExtensionRuntimeContext } from "@/extensions/types";
import type {
  ShippingProjectFile,
  ShippingProjectScenario,
} from "@/lib/shipping-project";

export function PanelGroup({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <section className="space-y-1.5">
      <div className="text-[9px] uppercase tracking-[0.16em] text-white/[0.3]">
        {title}
      </div>
      <div className="space-y-1">{children}</div>
    </section>
  );
}

export function ExplorerItem({
  label,
  detail,
  active = false,
  onClick,
}: {
  label: string;
  detail: string;
  active?: boolean;
  onClick?: () => void;
}) {
  const className = `w-full border px-2 py-1.5 text-left transition ${
    active
      ? "border-[rgba(143,194,198,0.3)] bg-[rgba(143,194,198,0.08)]"
      : "border-white/8 bg-white/[0.02] hover:border-white/[0.12] hover:bg-white/[0.04]"
  }`;

  if (onClick) {
    return (
      <button onClick={onClick} className={className}>
        <div className="text-[11px] text-white">{label}</div>
        <div className="mt-0.5 text-[10px] leading-4 text-white/[0.44]">
          {detail}
        </div>
      </button>
    );
  }

  return (
    <div className={className}>
      <div className="text-[11px] text-white">{label}</div>
      <div className="mt-0.5 text-[10px] leading-4 text-white/[0.44]">
        {detail}
      </div>
    </div>
  );
}

export function TreeSection({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <section className="space-y-0.5">
      <div className="px-2 text-[9px] uppercase tracking-[0.16em] text-white/[0.28]">
        {title}
      </div>
      <div>{children}</div>
    </section>
  );
}

export function TreeItem({
  label,
  meta,
  active = false,
  onClick,
  inset = 0,
}: {
  label: string;
  meta?: string;
  active?: boolean;
  onClick?: () => void;
  inset?: number;
}) {
  const className = `flex w-full items-center justify-between gap-2 px-2 py-1 text-left text-[10px] transition ${
    active
      ? "bg-[rgba(143,194,198,0.1)] text-white"
      : "text-white/[0.72] hover:bg-white/[0.04] hover:text-white"
  }`;

  const content = (
    <>
      <span
        className="min-w-0 truncate"
        style={{ paddingLeft: `${inset * 12}px` }}
      >
        {label}
      </span>
      {meta ? (
        <span className="shrink-0 text-[9px] text-white/[0.34]">{meta}</span>
      ) : null}
    </>
  );

  if (onClick) {
    return (
      <button onClick={onClick} className={className}>
        {content}
      </button>
    );
  }

  return <div className={className}>{content}</div>;
}

export function InspectorSection({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <section className="space-y-1">
      <div className="text-[9px] uppercase tracking-[0.16em] text-white/[0.3]">
        {title}
      </div>
      <div className="border border-white/8 bg-white/[0.02]">{children}</div>
    </section>
  );
}

export function PropertyRow({
  label,
  value,
}: {
  label: string;
  value: string;
}) {
  return (
    <div className="grid grid-cols-[0.85fr_1.15fr] items-center gap-2 border-b border-white/6 px-2 py-1 text-[10px] last:border-b-0">
      <span className="min-w-0 truncate text-white/[0.42]">{label}</span>
      <span className="min-w-0 truncate text-white/[0.82]">{value}</span>
    </div>
  );
}

export function ParameterEditor({
  entityName,
  parameterName,
  value,
  onChange,
}: {
  entityName: string;
  parameterName: string;
  value: string;
  onChange: (entityName: string, parameterName: string, value: string) => void;
}) {
  return (
    <div className="border-t border-white/6 px-2 py-2 first:border-t-0">
      <div className="mb-1 flex items-center justify-between gap-2">
        <div className="text-[10px] uppercase tracking-[0.14em] text-white/[0.34]">
          {parameterName}
        </div>
        <div className="text-[9px] text-white/[0.36]">parameter</div>
      </div>
      <input
        value={value}
        onChange={(event) =>
          onChange(entityName, parameterName, event.target.value)
        }
        className="w-full border border-white/8 bg-black/[0.16] px-2 py-1.5 text-[11px] text-white outline-none transition focus:border-[rgba(143,194,198,0.28)] focus:bg-black/[0.22]"
      />

      <div className="mt-1 text-[9px] leading-4 text-white/[0.42]">
        修改后可同步发送到运行时配置。
      </div>
    </div>
  );
}

export function WorkbenchNote({
  title,
  text,
}: {
  title: string;
  text: string;
}) {
  return (
    <div className="border border-white/8 bg-[rgba(10,15,22,0.72)] p-3">
      <div className="text-[10px] uppercase tracking-[0.16em] text-white/[0.34]">
        {title}
      </div>
      <p className="mt-2 text-[12px] leading-6 text-white/[0.58]">{text}</p>
    </div>
  );
}

export function LogLine({
  text,
  tone,
}: {
  text: string;
  tone: "neutral" | "warm" | "cool";
}) {
  const textClass =
    tone === "warm"
      ? "text-[#efc4ae]"
      : tone === "cool"
        ? "text-[#b8dfe2]"
        : "text-white/[0.6]";
  return (
    <div className="border border-white/8 bg-white/[0.03] px-2 py-1.5 font-mono text-[10px]">
      <span className={textClass}>{text}</span>
    </div>
  );
}

export function ProblemCard({ level, text }: { level: string; text: string }) {
  return (
    <div className="border border-white/8 bg-white/[0.03] px-2 py-2">
      <div className="text-[9px] uppercase tracking-[0.14em] text-white/[0.34]">
        {level}
      </div>
      <div className="mt-0.5 text-[10px] leading-5 text-white/[0.64]">
        {text}
      </div>
    </div>
  );
}

export function ExplorerPanel({
  modelName,
  modelEntities,
  connected,
  selectedEntityName,
  activeScenarioId,
  scenarios,
  onFetch,
  onSelectEntity,
  onOpenScenario,
  onApplyScenario,
}: {
  modelName?: string;
  modelEntities: Array<{
    name: string;
    parameter_count: number;
    port_count: number;
  }>;
  connected: boolean;
  selectedEntityName: string | null;
  activeScenarioId: string;
  scenarios: ShippingProjectScenario[];
  onFetch: () => void;
  onSelectEntity: (name: string) => void;
  onOpenScenario: (scenarioId: string) => void;
  onApplyScenario: (scenarioId: string) => void;
}) {
  return (
    <div className="space-y-3">
      <TreeSection title="Project">
        <TreeItem label="shipping-liner-demo" meta="example" />

        <TreeItem
          label={modelName ?? "Shipping model pending"}
          meta={connected ? "runtime" : "offline"}
          inset={1}
        />

        <TreeItem label="shipping extension" meta="enabled" inset={1} />
      </TreeSection>

      <TreeSection title="Scenarios">
        {scenarios.map((scenario) => (
          <div
            key={scenario.id}
            className="border-b border-white/6 last:border-b-0"
          >
            <TreeItem
              label={scenario.label}
              meta={activeScenarioId === scenario.id ? "active" : "preset"}
              active={activeScenarioId === scenario.id}
              onClick={() => onOpenScenario(scenario.id)}
            />

            <div className="px-2 pb-1">
              <button
                onClick={() => onApplyScenario(scenario.id)}
                className="text-[9px] uppercase tracking-[0.12em] text-white/[0.42] transition hover:text-white"
              >
                apply config
              </button>
            </div>
          </div>
        ))}
      </TreeSection>

      <TreeSection title="Components">
        {modelEntities.length > 0 ? (
          modelEntities.map((entity) => (
            <TreeItem
              key={entity.name}
              label={entity.name}
              meta={`${entity.parameter_count}p · ${entity.port_count}o`}
              active={selectedEntityName === entity.name}
              onClick={() => onSelectEntity(entity.name)}
            />
          ))
        ) : (
          <button
            onClick={onFetch}
            disabled={!connected}
            className="w-full border border-dashed border-white/10 px-2 py-2 text-left text-[10px] text-white/[0.5] transition hover:border-white/20 hover:text-white disabled:opacity-40"
          >
            拉取模型结构
          </button>
        )}
      </TreeSection>
    </div>
  );
}

export function ProjectFilesPanel({
  connected,
  projectPath,
  activePresetId,
  presets,
  activeExtensionLabel,
  files,
  activeFileId,
  onLoadPreset,
  onOpenFile,
}: {
  connected: boolean;
  projectPath: string | null;
  activePresetId: string | null;
  presets: Array<{ id: string; label: string; description?: string }>;
  activeExtensionLabel: string | null;
  files: ShippingProjectFile[];
  activeFileId: string | null;
  onLoadPreset: (presetId: string) => void;
  onOpenFile: (fileId: string) => void;
}) {
  const groups = [
    { id: "manifest", label: "Manifest" },
    { id: "docs", label: "Docs" },
    { id: "scenarios", label: "Scenarios" },
  ] as const;

  return (
    <div className="space-y-3">
      <div className="border border-white/8 bg-white/[0.02] p-2">
        <div className="text-[10px] uppercase tracking-[0.14em] text-white/[0.3]">
          Project Package
        </div>
        <div className="mt-1 text-[11px] leading-5 text-white/[0.56]">
          {projectPath ?? "examples/shipping-liner-demo"}
        </div>
        <div className="mt-2 text-[10px] text-white/[0.42]">
          {connected ? "runtime linked" : "offline"}{" "}
          {activeExtensionLabel ? `· ${activeExtensionLabel}` : ""}
        </div>
      </div>

      <TreeSection title="Project Files">
        {groups.map((group) => (
          <div
            key={group.id}
            className="border-b border-white/6 last:border-b-0"
          >
            <TreeItem
              label={group.label}
              meta={String(
                files.filter((file) => file.group === group.id).length,
              )}
            />

            {files
              .filter((file) => file.group === group.id)
              .map((file) => (
                <TreeItem
                  key={file.id}
                  label={file.label}
                  meta={file.language}
                  inset={1}
                  active={activeFileId === file.id}
                  onClick={() => onOpenFile(file.id)}
                />
              ))}
          </div>
        ))}
      </TreeSection>

      <PanelGroup title="Presets">
        {presets.map((preset) => (
          <ExplorerItem
            key={preset.id}
            label={preset.label}
            detail={preset.description ?? preset.id}
            active={activePresetId === preset.id}
            onClick={() => onLoadPreset(preset.id)}
          />
        ))}
      </PanelGroup>
    </div>
  );
}

export function SearchPanel({
  files,
  query,
  onQueryChange,
  onOpenResult,
}: {
  files: ShippingProjectFile[];
  query: string;
  onQueryChange: (value: string) => void;
  onOpenResult: (fileId: string) => void;
}) {
  const normalized = query.trim().toLowerCase();
  const results =
    normalized.length === 0
      ? []
      : files.filter((file) => {
          return (
            file.label.toLowerCase().includes(normalized) ||
            file.path.toLowerCase().includes(normalized) ||
            file.content.toLowerCase().includes(normalized)
          );
        });

  return (
    <div className="space-y-3">
      <div className="border border-white/8 bg-white/[0.02] px-2 py-1.5">
        <div className="text-[9px] uppercase tracking-[0.14em] text-white/[0.34]">
          Search
        </div>
        <input
          value={query}
          onChange={(event) => onQueryChange(event.target.value)}
          placeholder="route_id / preset / vessel / AEU3"
          className="mt-1 w-full bg-transparent text-[11px] text-white outline-none placeholder:text-white/[0.3]"
        />
      </div>

      {normalized.length === 0 ? (
        <WorkbenchNote
          title="Project Search"
          text="搜索项目文件、场景配置和说明文档。后续这里可继续接代码符号搜索与替换。"
        />
      ) : (
        <PanelGroup title={`Results · ${results.length}`}>
          {results.map((file) => (
            <ExplorerItem
              key={file.id}
              label={file.label}
              detail={file.path}
              onClick={() => onOpenResult(file.id)}
            />
          ))}
          {results.length === 0 ? (
            <div className="border border-dashed border-white/10 px-2 py-2 text-[10px] text-white/[0.46]">
              没有找到匹配内容。
            </div>
          ) : null}
        </PanelGroup>
      )}
    </div>
  );
}

export function SourceControlPanel({
  files,
  activeFileId,
  currentScenarioId,
}: {
  files: ShippingProjectFile[];
  activeFileId: string | null;
  currentScenarioId: string;
}) {
  return (
    <div className="space-y-3">
      <PanelGroup title="Working Tree">
        {files.map((file) => (
          <ExplorerItem
            key={file.id}
            label={file.label}
            detail={
              activeFileId === file.id ? "open in editor" : file.description
            }
            active={activeFileId === file.id}
          />
        ))}
      </PanelGroup>

      <WorkbenchNote
        title="Scenario Branching"
        text={`当前聚焦场景是 ${currentScenarioId}。后续 Git 视图可以把 scenario config、DSL patch 和运行输出一起组织成评审友好的变更集。`}
      />
    </div>
  );
}

export function ExtensionLibraryPanel({
  connected,
  hasErrors,
}: {
  connected: boolean;
  hasErrors: boolean;
}) {
  return (
    <div className="space-y-3">
      <PanelGroup title="Installed">
        <ExplorerItem
          label="Shipping"
          detail="Routes, ports, vessels, KPI panels and review scorecards"
          active
        />

        <ExplorerItem
          label="DEVS"
          detail="Discrete-event solver extension for packaged example projects"
        />

        <ExplorerItem
          label="Future Libraries"
          detail="Components, templates, solvers and renderers will be installed here."
        />
      </PanelGroup>

      <WorkbenchNote
        title="Extension Runtime"
        text={
          connected
            ? hasErrors
              ? "运行时已连接，但当前存在错误输出，适合继续把 diagnostics 与扩展修复回路接起来。"
              : "运行时和扩展视图已连通，下一步可以继续接安装、启停和版本管理。"
            : "先连接运行时，然后这里再继续接扩展启用状态、下载市场和模板安装。"
        }
      />
    </div>
  );
}

export function SimulationTreePanel({
  extensionViews,
  outputPorts,
  selectedEntityName,
  activePageId,
  onOpenView,
  onSelectEntity,
}: {
  extensionViews: Array<{
    id: string;
    label: string;
    placement: "workspace" | "dock" | "inspector";
  }>;
  outputPorts: Array<{ id: string; label: string; kind: string }>;
  selectedEntityName: string | null;
  activePageId: string | null;
  onOpenView: (viewId: string) => void;
  onSelectEntity: (entityName: string) => void;
}) {
  const structure = [
    { name: "DemandGenerator_AsiaLoop", kind: "Demand" },
    { name: "Port_Shanghai", kind: "Port" },
    { name: "Port_Singapore", kind: "Port" },
    { name: "Vessel_Surabaya", kind: "Vessel" },
    { name: "ShippingNetwork", kind: "Network" },
  ];

  return (
    <div className="space-y-3">
      <TreeSection title="DSL Structure">
        {structure.map((item) => (
          <TreeItem
            key={item.name}
            label={item.name}
            meta={item.kind}
            active={selectedEntityName === item.name}
            onClick={() => onSelectEntity(item.name)}
          />
        ))}
      </TreeSection>

      <TreeSection title="Extension Views">
        {extensionViews.map((view) => (
          <TreeItem
            key={view.id}
            label={view.label}
            meta={view.placement}
            active={activePageId === view.id}
            onClick={() => onOpenView(view.id)}
          />
        ))}
      </TreeSection>

      <TreeSection title="Output Ports">
        {outputPorts.length > 0 ? (
          outputPorts.map((port) => (
            <TreeItem key={port.id} label={port.label} meta={port.kind} />
          ))
        ) : (
          <TreeItem label="No output ports yet" meta="pending" />
        )}
      </TreeSection>
    </div>
  );
}

export function InspectorPanel({
  connected,
  modelName,
  mode,
  entityCount,
  selectedEntity,
  selectedRuntimeEntity,
  activeScenario,
  projectSummary,
  outputPorts,
  parameterDirty,
  getParameterDraft,
  onParameterDraftChange,
  onApplyConfig,
}: {
  connected: boolean;
  modelName?: string;
  mode: SimMode;
  entityCount: number;
  selectedEntity: {
    name: string;
    parameters: Array<{ name: string; type: string }>;
    port_count: number;
  } | null;
  selectedRuntimeEntity: [string, Record<string, unknown>] | null;
  activeScenario: ShippingProjectScenario | null;
  projectSummary: string;
  outputPorts: Array<{ id: string; label: string; kind: string }>;
  parameterDirty: boolean;
  getParameterDraft: (
    entityName: string,
    parameterName: string,
    fallbackType: string,
  ) => string;
  onParameterDraftChange: (
    entityName: string,
    parameterName: string,
    value: string,
  ) => void;
  onApplyConfig: () => void;
}) {
  return (
    <div className="flex h-full flex-col">
      <div className="border-b border-white/8 px-3 py-2">
        <div className="text-[10px] uppercase tracking-[0.18em] text-white/[0.34]">
          Inspector
        </div>
        <div className="mt-0.5 text-[14px] text-white">Properties</div>
      </div>
      <div className="flex-1 overflow-auto px-3 py-3">
        <div className="space-y-3">
          <InspectorSection title="Session">
            <PropertyRow
              label="Connection"
              value={connected ? "Linked" : "Offline"}
            />

            <PropertyRow
              label="Mode"
              value={mode === "academic" ? "Academic" : "Realtime"}
            />

            <PropertyRow label="Entities" value={String(entityCount)} />

            <PropertyRow label="Model" value={modelName ?? "No model"} />
          </InspectorSection>

          <InspectorSection title="Project">
            <PropertyRow
              label="Scenario"
              value={activeScenario?.label ?? "--"}
            />

            <PropertyRow label="Outputs" value={String(outputPorts.length)} />

            <PropertyRow label="Package" value={projectSummary} />
          </InspectorSection>

          <InspectorSection title="Selected Component">
            {selectedEntity ? (
              <>
                <PropertyRow label="Name" value={selectedEntity.name} />

                <PropertyRow
                  label="Ports"
                  value={String(selectedEntity.port_count)}
                />

                {selectedEntity.parameters.map((parameter) => (
                  <ParameterEditor
                    key={parameter.name}
                    entityName={selectedEntity.name}
                    parameterName={parameter.name}
                    value={getParameterDraft(
                      selectedEntity.name,
                      parameter.name,
                      parameter.type,
                    )}
                    onChange={onParameterDraftChange}
                  />
                ))}
                <div className="border-t border-white/6 px-2 py-2">
                  <button
                    onClick={onApplyConfig}
                    disabled={!parameterDirty}
                    className="w-full border border-white/10 bg-white/[0.04] px-2 py-1.5 text-[11px] text-white transition hover:bg-white/[0.08] disabled:cursor-not-allowed disabled:opacity-35"
                  >
                    Apply to Runtime
                  </button>
                </div>
              </>
            ) : (
              <div className="px-2 py-2 text-[10px] text-white/[0.46]">
                选择组件后显示属性。
              </div>
            )}
          </InspectorSection>

          <InspectorSection title="Runtime Focus">
            {selectedRuntimeEntity ? (
              Object.entries(selectedRuntimeEntity[1])
                .slice(0, 10)
                .map(([key, value]) => (
                  <PropertyRow
                    key={key}
                    label={key}
                    value={formatValue(value)}
                  />
                ))
            ) : (
              <div className="px-2 py-2 text-[10px] text-white/[0.46]">
                运行后显示执行态字段。
              </div>
            )}
          </InspectorSection>
        </div>
      </div>
    </div>
  );
}

export function WorkbenchDock({
  activeTab,
  onTabChange,
  extraTabs = [],
  eventsPanel,
  logsPanel,
  problemsPanel,
}: {
  activeTab: string;
  onTabChange: (tab: string) => void;
  extraTabs?: Array<{ id: string; label: string; content: ReactNode }>;
  eventsPanel: ReactNode;
  logsPanel: ReactNode;
  problemsPanel: ReactNode;
}) {
  const tabs = [
    { id: "events", label: "Events", content: eventsPanel },
    ...extraTabs,
    { id: "logs", label: "Logs", content: logsPanel },
    { id: "problems", label: "Problems", content: problemsPanel },
  ];

  const active = tabs.find((tab) => tab.id === activeTab) ?? tabs[0];

  return (
    <div className="h-full border-t border-white/8 bg-[rgba(11,14,20,0.96)]">
      <div className="flex items-center gap-1 overflow-x-auto border-b border-white/8 px-2 py-1.5">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => onTabChange(tab.id)}
            className={`px-2 py-1 text-[11px] transition ${
              active.id === tab.id
                ? "bg-white/[0.08] text-white"
                : "text-white/[0.46] hover:bg-white/[0.04] hover:text-white"
            }`}
          >
            {tab.label}
          </button>
        ))}
      </div>
      <div className="h-[calc(100%-34px)] overflow-auto p-1.5">
        {active.content}
      </div>
    </div>
  );
}

export function EventsPanel({
  runtimeEntities,
}: {
  runtimeEntities: Array<[string, Record<string, unknown>]>;
}) {
  return (
    <div className="space-y-1">
      {runtimeEntities.slice(0, 12).map(([name, state]) => (
        <div
          key={name}
          className="grid grid-cols-[1.2fr_0.8fr_0.8fr] items-center gap-2 border border-white/8 bg-white/[0.03] px-2 py-1.5 text-[10px]"
        >
          <span className="truncate text-white">{name}</span>
          <span className="font-mono text-white/[0.5]">
            {(state._phase as string | undefined) ?? "phase?"}
          </span>
          <span className="font-mono text-white/[0.42]">
            {typeof state._sigma === "number" ? state._sigma.toFixed(2) : "--"}
          </span>
        </div>
      ))}
      {runtimeEntities.length === 0 ? (
        <div className="border border-dashed border-white/10 p-2 text-[10px] text-white/[0.48]">
          运行开始后展示事件流与推进。
        </div>
      ) : null}
    </div>
  );
}

export function LogsPanel({
  connected,
  error,
}: {
  connected: boolean;
  error: string | null;
}) {
  return (
    <div className="space-y-1">
      <LogLine
        tone="neutral"
        text={
          connected
            ? "runtime link established"
            : "runtime link not established"
        }
      />

      <LogLine tone="cool" text="shipping workbench mounted" />

      <LogLine
        tone={error ? "warm" : "cool"}
        text={error ? `diagnostic: ${error}` : "diagnostic channel idle"}
      />
    </div>
  );
}

export function ProblemsPanel({
  error,
  connected,
  modelLoaded,
}: {
  error: string | null;
  connected: boolean;
  modelLoaded: boolean;
}) {
  return (
    <div className="space-y-1">
      {error ? <ProblemCard level="Error" text={error} /> : null}
      {!connected ? (
        <ProblemCard
          level="Info"
          text="运行时未连接，当前只能浏览 shipping 项目和界面壳层。"
        />
      ) : null}
      {!modelLoaded ? (
        <ProblemCard
          level="Info"
          text="模型结构尚未拉取，Explorer / Sim Tree 仍未进入运行态。"
        />
      ) : null}
      {!error && connected && modelLoaded ? (
        <ProblemCard
          level="OK"
          text="海运示例的项目包、运行时和专题视图已经连通。"
        />
      ) : null}
    </div>
  );
}

export function ExtensionDockPanel({
  context,
  extensionViews,
}: {
  context: ExtensionRuntimeContext | null;
  extensionViews: Array<{
    id: string;
    label: string;
    placement: "workspace" | "dock" | "inspector";
    Component: ComponentType<{ context: ExtensionRuntimeContext }>;
  }>;
}) {
  if (!context || extensionViews.length === 0) {
    return (
      <WorkbenchNote
        title="Extension Dock"
        text="当前没有可挂接到底部输出栏的领域面板。"
      />
    );
  }

  return (
    <div className="space-y-1.5">
      {extensionViews.map((view) => (
        <div key={view.id}>
          <view.Component context={context} />
        </div>
      ))}
    </div>
  );
}
