import { describe, expect, it } from "vitest";
import { detectOvernightPlaces, type VisitPoint } from "./places";

const PLACE_A = { lat: 37.3317, lng: -121.8929 };
const PLACE_B = { lat: 37.3417, lng: -121.8929 };
const DAYTIME_POINT = { lat: 37.5, lng: -121.7 };

function localPoint(
  day: number,
  hour: number,
  place: typeof PLACE_A,
): VisitPoint {
  return {
    ...place,
    recorded_at: new Date(2026, 0, day, hour, 0).toISOString(),
  };
}

function addNight(
  points: VisitPoint[],
  day: number,
  place: typeof PLACE_A,
  endHour = 6,
) {
  points.push(
    localPoint(day, 1, place),
    localPoint(day, endHour, place),
    // A distant daytime fix closes the overnight stay before the next night.
    localPoint(day, 12, DAYTIME_POINT),
  );
}

describe("detectOvernightPlaces", () => {
  it("shows where the user stayed overnight and the number of nights", () => {
    const points: VisitPoint[] = [];
    for (let day = 1; day <= 3; day += 1) addNight(points, day, PLACE_A);
    for (let day = 4; day <= 5; day += 1) addNight(points, day, PLACE_B);

    const places = detectOvernightPlaces(points);

    expect(places).toEqual([
      expect.objectContaining({ ...PLACE_A, kind: "overnight", score: 3 }),
      expect.objectContaining({ ...PLACE_B, kind: "overnight", score: 2 }),
    ]);
  });

  it("ignores overnight stays shorter than five hours", () => {
    const points: VisitPoint[] = [];
    for (let day = 1; day <= 10; day += 1) addNight(points, day, PLACE_A, 5);

    expect(detectOvernightPlaces(points)).toEqual([]);
  });

  it("emits only overnight place records", () => {
    const points: VisitPoint[] = [];
    addNight(points, 1, PLACE_A);

    expect(detectOvernightPlaces(points).every((p) => p.kind === "overnight")).toBe(true);
  });
});
