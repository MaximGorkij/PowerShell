// Add this type stub for local development if ExcelScript is not available
declare namespace ExcelScript {
  interface Workbook {
    getActiveWorksheet(): Worksheet;
  }
  interface Worksheet {
    getRange(address: string): Range;
    getUsedRange(): Range;
    getRangeByIndexes(row: number, col: number, rowCount: number, colCount: number): Range;
    addTable(address: string, hasHeaders: boolean): Table;
  }
  interface Range {
    setValue(value: any): void;
    getValues(): any[][];
    getRowCount(): number;
    getColumnCount(): number;
    getFormat(): Format;
    getAddress(): string;
  }
  interface Format {
    autofitColumns(): void;
  }
  interface Table {
    setName(name: string): void;
  }
}

function main(workbook: ExcelScript.Workbook) {
  let sheet = workbook.getActiveWorksheet();
  const today = new Date();
  const formattedDate = today.toLocaleDateString("sk-SK", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
  });
  sheet.getRange("A1").setValue(`Dátum spracovania: ${formattedDate}`);

  const usedRange = sheet.getUsedRange();
  if (usedRange) {
    const rowCount = usedRange.getRowCount();
    const columnCount = usedRange.getColumnCount();
    const data = usedRange.getValues();
    for (let i = 0; i < rowCount; i++) {
      sheet.getRangeByIndexes(1 + i, 0, 1, columnCount).setValue(data[i]);
    }
  }

  sheet.getUsedRange().getFormat().autofitColumns();
  const finalRange = sheet.getUsedRange();
  const table = sheet.addTable(finalRange.getAddress(), true);
  table.setName("InactiveUsersTable");
}