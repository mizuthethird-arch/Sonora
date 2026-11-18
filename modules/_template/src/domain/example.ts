export const MAX_TITLE_LENGTH = 80;

export type Example = {
  readonly id: string;
  readonly title: string;
};

const CONTROL_CHARACTERS = /[\u0000-\u001f\u007f]/;

// Checks and trims a title. Throws when it is empty, too long or contains control characters.
export function parseExampleTitle(input: string): string {
  const title = input.trim();
  if (title.length === 0) {
    throw new Error("title must not be empty");
  }
  if (title.length > MAX_TITLE_LENGTH) {
    throw new Error(`title must be at most ${MAX_TITLE_LENGTH} characters`);
  }
  if (CONTROL_CHARACTERS.test(title)) {
    throw new Error("title must not contain control characters");
  }
  return title;
}
