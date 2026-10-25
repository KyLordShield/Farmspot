/// Uses the space available to the grid, including split-screen windows.
int listingGridColumns(double width) {
  if (width >= 900) return 4;
  if (width >= 600) return 3;
  return 2;
}
