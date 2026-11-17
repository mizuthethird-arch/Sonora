import ts from "typescript";

const EVENT_SCHEMA_SUFFIX = "EventSchema";

/**
 * Lists what a module public entry exports besides its facade, its types and its event schemas.
 * The source is read as syntax only, so nothing is imported or run.
 */
export function findForbiddenExports(sourceText: string): string[] {
  const file = ts.createSourceFile("public-entry.ts", sourceText, ts.ScriptTarget.Latest, true);
  return file.statements.flatMap(describeForbiddenExports);
}

function describeForbiddenExports(statement: ts.Statement): string[] {
  if (ts.isExportDeclaration(statement)) {
    return forbiddenInExportDeclaration(statement);
  }
  if (ts.isExportAssignment(statement)) {
    return ["default export"];
  }
  if (!isExported(statement)) {
    return [];
  }
  if (ts.isInterfaceDeclaration(statement) || ts.isTypeAliasDeclaration(statement)) {
    return [];
  }
  if (ts.isVariableStatement(statement)) {
    const names = statement.declarationList.declarations.map((declaration) => declaration.name.getText());
    return names.filter(isNotEventSchema);
  }
  return [`${ts.SyntaxKind[statement.kind]} export`];
}

function forbiddenInExportDeclaration(declaration: ts.ExportDeclaration): string[] {
  const clause = declaration.exportClause;

  if (declaration.isTypeOnly) {
    return [];
  }
  if (!clause || ts.isNamespaceExport(clause)) {
    return ["star re-export"];
  }
  const valueElements = clause.elements.filter((element) => !element.isTypeOnly);
  const exportedNames = valueElements.map((element) => (element.propertyName ?? element.name).text);
  return exportedNames.filter(isNotEventSchema);
}

function isExported(statement: ts.Statement): boolean {
  const modifiers = ts.canHaveModifiers(statement) ? ts.getModifiers(statement) : undefined;
  return modifiers?.some((modifier) => modifier.kind === ts.SyntaxKind.ExportKeyword) ?? false;
}

function isNotEventSchema(name: string): boolean {
  return !name.endsWith(EVENT_SCHEMA_SUFFIX);
}
