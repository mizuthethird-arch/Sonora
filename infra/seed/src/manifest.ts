import { z } from "zod";

const TrackSchema = z.object({
  id: z.string().min(1),
  title: z.string().min(1),
  artist: z.string().min(1),
  licenseCode: z.string().min(1),
  sourcePageUrl: z.httpUrl(),
  downloadUrl: z.httpUrl(),
  sha256: z.string().regex(/^[0-9a-f]{64}$/),
});

const ManifestSchema = z
  .array(TrackSchema)
  .refine((tracks) => new Set(tracks.map((track) => track.id)).size === tracks.length, {
    message: "track ids must be unique",
  });

export type Track = z.infer<typeof TrackSchema>;

export function parseManifest(json: unknown): Track[] {
  return ManifestSchema.parse(json);
}
