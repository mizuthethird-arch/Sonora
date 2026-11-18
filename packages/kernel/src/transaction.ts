// A module passes its own database handle here, so a transaction never spans two module databases.
export type TransactionalDatabase<Tx> = {
  readonly moduleDatabase: string;
  begin: () => Promise<Tx>;
  commit: (transaction: Tx) => Promise<void>;
  rollback: (transaction: Tx) => Promise<void>;
};

// Commits when the work resolves. Rolls back and rethrows the original error when it rejects.
export async function runInTransaction<Tx, Result>(
  database: TransactionalDatabase<Tx>,
  work: (transaction: Tx) => Promise<Result>,
): Promise<Result> {
  const transaction = await database.begin();
  try {
    const result = await work(transaction);
    await database.commit(transaction);
    return result;
  } catch (error) {
    await database.rollback(transaction);
    throw error;
  }
}
