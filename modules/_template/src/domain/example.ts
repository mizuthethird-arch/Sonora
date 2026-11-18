export const MAX_TITLE_LENGTH = 80;

export type Example = {
  readonly id: string;
  readonly title: string;
};

const DELETE_CHARACTER_CODE = 127;
const LAST_CONTROL_CHARACTER_CODE = 31;

function hasControlCharacter(text: string): boolean {
  return [...text].some((character) => {
    const code = character.charCodeAt(0);
    return code <= LAST_CONTROL_CHARACTER_CODE || code === DELETE_CHARACTER_CODE;
  });
}

// Checks and trims a title. Throws when it is empty, too long or contains control characters.
export function parseExampleTitle(input: string): string {
  const title = input.trim();
  if (title.length === 0) {
    throw new Error("title must not be empty");
  }
  if (title.length > MAX_TITLE_LENGTH) {
    throw new Error(`title must be at most ${MAX_TITLE_LENGTH} characters`);
  }
  if (hasControlCharacter(title)) {
    throw new Error("title must not contain control characters");
  }
  return title;
}
