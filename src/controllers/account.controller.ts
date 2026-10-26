import { Get, JsonController, NotFoundError, QueryParam, UseBefore } from "routing-controllers";
import { Service } from "typedi";
import type { Account } from "../interfaces/account.js";
import { ApiKeyMiddleware } from "../middleware/api-key.middleware.js";
import { AccountService } from "../services/account.service.js";

@Service()
@JsonController("/getAccount")
@UseBefore(ApiKeyMiddleware)
export class AccountController {
  constructor(private readonly accountService: AccountService) {}

  @Get()
  getAccount(@QueryParam("id") id?: string): Account | { count: number; accounts: Account[] } {
    if (id === undefined) {
      const accounts = this.accountService.findAll();
      return { count: accounts.length, accounts };
    }

    const account = this.accountService.findById(id);
    if (!account) {
      throw new NotFoundError(`Account with id '${id}' not found`);
    }
    return account;
  }
}
