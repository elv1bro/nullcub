import type { LocaleStrings } from "@/i18n/types";
import type { WorkshopTool } from "@/workshop/useWorkshopValidation";
import {
  LINK_COLORS,
  LINK_TYPE_ORDER,
  type MonsterLinkType,
} from "@/monster/linkTypes";

type Props = {
  t: LocaleStrings["workshop"];
  tool: WorkshopTool;
  onToolChange: (tool: WorkshopTool) => void;
  linkType: MonsterLinkType;
  onLinkTypeChange: (type: MonsterLinkType) => void;
  disabled?: boolean;
};

export function WorkshopToolBar({
  t,
  tool,
  onToolChange,
  linkType,
  onLinkTypeChange,
  disabled,
}: Props) {
  const linkLabel = (type: MonsterLinkType) => {
    if (type === "rigid") return t.linkRigid;
    if (type === "spring") return t.linkSpring;
    return t.linkRope;
  };
  const linkDesc = (type: MonsterLinkType) => {
    if (type === "rigid") return t.linkRigidDesc;
    if (type === "spring") return t.linkSpringDesc;
    return t.linkRopeDesc;
  };

  return (
    <div className="ws-toolbar">
      <div className="ws-toolbar__modes">
        <button
          type="button"
          className={[
            "ws-tool-btn",
            tool === "move" ? "ws-tool-btn--active" : "",
          ].join(" ")}
          disabled={disabled}
          onClick={() => onToolChange("move")}
        >
          {t.toolMove}
        </button>
        <button
          type="button"
          className={[
            "ws-tool-btn",
            tool === "link" ? "ws-tool-btn--active" : "",
          ].join(" ")}
          disabled={disabled}
          onClick={() => onToolChange("link")}
        >
          {t.toolLink}
        </button>
      </div>
      <p className="ws-toolbar__hint">
        {tool === "move" ? t.toolMoveHint : t.toolLinkHint}
      </p>
      <div className="ws-link-pills">
        <span className="ws-link-pills__label">{t.linkType}</span>
        <div className="ws-link-pills__row">
          {LINK_TYPE_ORDER.map((type) => (
            <button
              key={type}
              type="button"
              className={[
                "ws-link-pill",
                linkType === type ? "ws-link-pill--active" : "",
              ].join(" ")}
              style={
                linkType === type
                  ? { borderColor: LINK_COLORS[type], color: LINK_COLORS[type] }
                  : undefined
              }
              onClick={() => onLinkTypeChange(type)}
              disabled={disabled}
              title={linkDesc(type)}
            >
              {linkLabel(type)}
            </button>
          ))}
        </div>
        <p className="ws-link-pills__hint">{linkDesc(linkType)}</p>
      </div>
    </div>
  );
}
