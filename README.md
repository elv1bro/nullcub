# Ragdoll Faces

Форк [onedoes/ragdollmasters](https://github.com/onedoes/ragdollmasters) (WTFPL) с нашими доработками:

- **HP и урон** — полоски здоровья, нокаут, победа/поражение
- **Лицо с вебки** — MediaPipe Face Landmarker → мимика на голове рэгдолла
- **Эмоции** — злость, улыбка, испуг, боль (реакция на удары)

## Запуск

```bash
corepack enable
yarn install
yarn dev
```

Меню → **Play** → **1 Player**. Управление — стрелки. Разрешите доступ к вебке для мимики.

## Тесты

```bash
yarn test
```

## Дальше

См. [docs/ROADMAP.md](docs/ROADMAP.md) — предметы, мутаторы, кампания, сеть.
