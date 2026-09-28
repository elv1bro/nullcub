import Matter, { Body } from "matter-js";

export class Particle {
  body: Body;
  life = 1;

  constructor(x: number, y: number, r: number, fillStyle = "#f00") {
    this.body = Matter.Bodies.circle(x, y, r, {
      friction: 0,
      restitution: 0.35,
      // Быстрее гаснут в воздухе — меньше «мусора» в мире на серии ударов.
      frictionAir: 0.035,
      density: 0.001,
      // Не участвуют в коллизиях (category 0 ∧ mask 0), но Matter всё равно
      // интегрирует тело — жизнь поэтому короткая, см. update().
      collisionFilter: { category: 0, mask: 0 },
      render: { fillStyle, opacity: 1 },
    });
  }

  update(event: Matter.IEventTimestamped<Matter.Engine>) {
    const dtMs = ((event as { delta?: number }).delta || 1000 / 60);
    // ~1.1 с жизни вместо ~10 с: на комбо иначе копится сотня тел и FPS падает.
    const lifeScale = dtMs / 1100;
    this.life -= lifeScale;
    this.body.render.opacity = this.life;

    // Replay держит engine.timing.timeScale = 0 — Matter не двигает тела,
    // кругляши сдвигаем сами (лёгкая «гравитация» + затухание).
    const engine = event.source;
    if (engine.timing.timeScale < 1e-6) {
      const dt = dtMs / 1000;
      const vx = this.body.velocity.x;
      const vy = this.body.velocity.y + 420 * dt;
      Body.setVelocity(this.body, { x: vx * 0.985, y: vy * 0.985 });
      Body.setPosition(this.body, {
        x: this.body.position.x + vx * dt,
        y: this.body.position.y + vy * dt,
      });
    }
  }
}
