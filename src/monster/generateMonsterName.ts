const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

/** «MONSTER X7K2» — имя по умолчанию для нового чертежа. */
export function generateMonsterName(): string {
  let code = "";
  for (let i = 0; i < 4; i++) {
    code += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)]!;
  }
  return `MONSTER ${code}`;
}
