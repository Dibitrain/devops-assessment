import { Service } from "typedi";
import type { Account } from "../interfaces/account.js";

@Service()
export class AccountService {
  private readonly accounts: Account[] = [
    {
      id: "66ab443c4d4ac0b1cdf45691",
      account_name: "Samuel Olumide",
      account_number: "0091533000",
      balance: 2500.75,
      currency: "NGN",
    },
    {
      id: "66ab443c4d4ac0b1cdf45692",
      account_name: "Samuel Olumide",
      account_number: "0091533001",
      balance: 2500.75,
      currency: "NGN",
    },
    {
      id: "66ab443c4d4ac0b1cdf45693",
      account_name: "Samuel Olumide",
      account_number: "0091533002",
      balance: 2500.75,
      currency: "NGN",
    },
  ];

  findAll(): Account[] {
    return this.accounts;
  }

  findById(id: string): Account | undefined {
    return this.accounts.find((account) => account.id === id);
  }
}
