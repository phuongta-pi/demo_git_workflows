/**
 * Admin Module: Filter state management
 * PR #3940 - fix(admin): filter không refill (Issue #3938)
 * Fix: preserve filter state across list re-renders without clearing user inputs.
 */

export interface ResidentFilterCriteria {
  buildingBlock?: string;
  floor?: number;
  paymentStatus?: 'PAID' | 'PENDING' | 'OVERDUE';
  searchQuery?: string;
}

export class ResidentFilterManager {
  private savedCriteria: ResidentFilterCriteria = {};

  public applyFilter(criteria: ResidentFilterCriteria): ResidentFilterCriteria {
    // Preserve existing valid values rather than resetting to empty
    this.savedCriteria = {
      ...this.savedCriteria,
      ...criteria,
    };
    return { ...this.savedCriteria };
  }

  public getSavedFilter(): ResidentFilterCriteria {
    return { ...this.savedCriteria };
  }

  public resetFilter(): void {
    this.savedCriteria = {};
  }
}
