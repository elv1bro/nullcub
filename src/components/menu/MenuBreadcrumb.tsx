interface Props {
  home: string;
  current: string;
  onHome?: () => void;
}

export function MenuBreadcrumb({ home, current, onHome }: Props) {
  return (
    <nav className="menu-breadcrumb font-ui" aria-label="Breadcrumb">
      {onHome ? (
        <button type="button" className="menu-breadcrumb__home" onClick={onHome}>
          {home}
        </button>
      ) : (
        <span>{home}</span>
      )}
      <span className="menu-breadcrumb__sep" aria-hidden>
        ›
      </span>
      <span className="menu-breadcrumb__current">{current}</span>
    </nav>
  );
}
