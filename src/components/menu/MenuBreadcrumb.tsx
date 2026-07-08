interface Props {
  home: string;
  current: string;
}

export function MenuBreadcrumb({ home, current }: Props) {
  return (
    <nav className="menu-breadcrumb font-ui" aria-label="Breadcrumb">
      <span>{home}</span>
      <span className="menu-breadcrumb__sep" aria-hidden>
        ›
      </span>
      <span className="menu-breadcrumb__current">{current}</span>
    </nav>
  );
}
