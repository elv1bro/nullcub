import { describe, expect, it } from "vitest";
import {
  deviceRenderPixelRatio,
  RENDER_PIXEL_RATIO_CAP,
} from "./setRenderPixelRatio";

describe("deviceRenderPixelRatio", () => {
  it("caps high DPR phones", () => {
    expect(deviceRenderPixelRatio(3)).toBe(RENDER_PIXEL_RATIO_CAP);
    expect(deviceRenderPixelRatio(2.625)).toBe(RENDER_PIXEL_RATIO_CAP);
  });

  it("keeps 1x and 2x", () => {
    expect(deviceRenderPixelRatio(1)).toBe(1);
    expect(deviceRenderPixelRatio(2)).toBe(2);
  });
});
