import { HeadObjectCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import type { Storage } from "./seed.ts";

export type S3StorageOptions = { endpoint: string; bucket: string; region: string };

// HeadObject reports a missing object as an error named NotFound.
function isNotFound(error: unknown): boolean {
  return error instanceof Error && error.name === "NotFound";
}

export function createS3Storage(options: S3StorageOptions): Storage {
  const client = new S3Client({
    endpoint: options.endpoint,
    region: options.region,
    forcePathStyle: true,
  });

  return {
    async has(key, sha256) {
      try {
        const head = await client.send(new HeadObjectCommand({ Bucket: options.bucket, Key: key }));
        return head.Metadata?.sha256 === sha256;
      } catch (error) {
        if (isNotFound(error)) {
          return false;
        }
        throw error;
      }
    },
    async put(key, body, sha256) {
      await client.send(
        new PutObjectCommand({
          Bucket: options.bucket,
          Key: key,
          Body: body,
          Metadata: { sha256 },
        }),
      );
    },
  };
}
