import type { PlaybackFacade } from "../../playback/src/public/index.js";

export const playbackName = "playback" as const;
export type Dependency = PlaybackFacade;
