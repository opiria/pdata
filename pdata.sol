pragma solidity ^0.4.13;

/**
 * Overflow aware uint math functions.
 *
 * Inspired by https://github.com/MakerDAO/maker-otc/blob/master/contracts/simple_market.sol
 */
contract SafeMath {
    //internals

    function safeMul(uint a, uint b) internal returns (uint) {
        uint c = a * b;
        require(a == 0 || c / a == b);
        return c;
    }

    function safeSub(uint a, uint b) internal returns (uint) {
        require(b <= a);
        return a - b;
    }

    function safeAdd(uint a, uint b) internal returns (uint) {
        uint c = a + b;
        require(c>=a && c>=b);
        return c;
    }

    function safeDiv(uint a, uint b) internal returns (uint) {
        require(b > 0);
        uint c = a / b;
        require(a == b * c + a % b);
        return c;
    }
}


/**
 * ERC 20 token
 *
 * https://github.com/ethereum/EIPs/issues/20
 */
interface Token {

    /// @return total amount of tokens
    // function totalSupply() constant returns (uint256 supply);

    /// @param _owner The address from which the balance will be retrieved
    /// @return The balance
    function balanceOf(address _owner) constant returns (uint256 balance);

    /// @notice send `_value` token to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transfer(address _to, uint256 _value) returns (bool success);

    /// @notice send `_value` token to `_to` from `_from` on the condition it is approved by `_from`
    /// @param _from The address of the sender
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success);

    /// @notice `msg.sender` approves `_addr` to spend `_value` tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @param _value The amount of wei to be approved for transfer
    /// @return Whether the approval was successful or not
    function approve(address _spender, uint256 _value) returns (bool success);

    /// @param _owner The address of the account owning tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @return Amount of remaining tokens allowed to spent
    function allowance(address _owner, address _spender) constant returns (uint256 remaining);

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

}

/**
 * ERC 20 token
 *
 * https://github.com/ethereum/EIPs/issues/20
 */
contract StandardToken is Token {

    /**
     * Reviewed:
     * - Integer overflow = OK, checked
     */
    function transfer(address _to, uint256 _value) returns (bool success) {
        //Default assumes totalSupply can't be over max (2^256 - 1).
        //If your token leaves out totalSupply and can issue more tokens as time goes on, you need to check if it doesn't wrap.
        //Replace the if with this one instead.
        if (balances[msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
            //if (balances[msg.sender] >= _value && _value > 0) {
            balances[msg.sender] -= _value;
            balances[_to] += _value;
            Transfer(msg.sender, _to, _value);
            return true;
        } else { return false; }
    }

    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
        //same as above. Replace this line with the following if you want to protect against wrapping uints.
        if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
            //if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && _value > 0) {
            balances[_to] += _value;
            balances[_from] -= _value;
            allowed[_from][msg.sender] -= _value;
            Transfer(_from, _to, _value);
            return true;
        } else { return false; }
    }

    function balanceOf(address _owner) constant returns (uint256 balance) {
        return balances[_owner];
    }

    function approve(address _spender, uint256 _value) returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    mapping(address => uint256) balances;

    mapping (address => mapping (address => uint256)) allowed;

    uint256 public totalSupply;
}


/**
 * PDATA crowdsale ICO contract.
 *
 * Security criteria evaluated against http://ethereum.stackexchange.com/questions/8551/methodological-security-review-of-a-smart-contract
 *
 *
 */
contract PDATAToken is StandardToken, SafeMath {

    string public name = "PDATA Token";
    string public symbol = "PDATA";

    // Initial founder address (set in constructor)
    // This address is used as a controller address, in order to properly handle administration of the token.
    address public founder = 0x0;

    // Deposit Address - The funds will be sent here immediately after payments are made to the contract
    address public deposit = 0x0;

    /*
    Multi-stage sale contract.

    Notes:
    All token sales are tied to USD.  No token sales are for a fixed amount of Wei, this can shift and change over time.
    Due to this, the following needs to be paid attention to:
    1. The value of the token fluctuates in reference to the centsPerEth set on the contract.
    2. The tokens are priced in cents.  So all token purchases will be calculated out live at that time.

    CAP:
    The  Sale  Period  will  begin  on March 26 th  at  8am  New  York  time,  2018  and continue  until either
    (a)  USD  19  million  worth  of  Ether  or  Bitcoin  are  received  for  PDATA  Tokens  sold
    (b)  May 7th, 2018 8am New York time.

    PRICE:
    We will create roughly 650 million PDATA tokens.
    PDATA token is worth $0.1 dollars (10 US cents).

    BONUS:
    Day  1  of  the  ICO  the bonus will  be  40%.
    Each  day  the bonus will  go  down  by 1% down to a minimum of 0%. 
    The last 3 days of the ICO there will be no more bonus

    TOKEN DISTRIBUTION:
    issued: 50% of the coins will be issued for the ICO
    Reserves: 30% will be used for data purchase
    Company/Team: 20% will be used for research and development

    POST-SALE 20% token usage:
    25% of them will be available in the same time as for the public, roughly 1 month after the CTL.
    25% of them will be locked for 12 months
    25% of them will be locked for 24 months
    25% of them will be locked for 36 months

    Purchased tokens come available to be withdrawn 31 days after the sale has completed.
    */

    enum State { PreSale, Sale, Running, Halted } // the states through which this contract goes
    State state;

    // Pricing for the pre-sale in US Cents.
    uint public capPreSale = 5 * 10**8;  // 15M USD cap for pre-sale, this subtracts from day1 cap
    uint public capTotal = 19 * 10**8;  // 20M USD cap

    // Token pricing information
    uint public weiPerEther = 10**18;
    uint public centsPerEth = 70000;
    uint public centsPerToken = 10;

    uint public subdivisions = 10**9;

    // Amount of funds raised in stages of pre-sale
    uint public raisePreSale = 0;  // USD raise during the pre-sale period
    uint public raiseSale = 0;  // USD raised during the sale period

    // Block timing/contract unlocking information
    uint public publicSaleStart = 1522069200; // Monday, March 26, 2018 1:00:00 PM GMT
    uint public saleEnd = 1525698000; // Monday, May 7, 2018 1:00:00 PM GMT

    uint public coinTradeStart = publicSaleStart + (3600 * 24 * 56); // 56 days later
    uint public year1Unlock = 1557234000; // Tuesday, May 7, 2019 1:00:00 PM GMT
    uint public year2Unlock = 1588856400; // Thursday, May 7, 2020 1:00:00 PM GMT
    uint public year3Unlock = 1620392400; // Friday, May 7, 2021 1:00:00 PM GMT
    uint public year4Unlock = 1651928400; // Saturday, May 7, 2022 1:00:00 PM GMT

    // Have the post-reward allocations been completed
    bool public allocatedFounders = false;
    bool public allocated1Year = false;
    bool public allocated2Year = false;
    bool public allocated3Year = false;
    bool public allocated4Year = false;

    // Token count information
    uint public totalTokensSale = 500000000; //total number of tokens being sold in the ICO, excluding bonuses, reserve, and team distributions
    uint public totalTokensReserve = 330000000;
    uint public totalTokensCompany = 220000000;

    bool public halted = false; //the founder address can set this to true to halt the crowdsale due to emergency.

    mapping(address => uint256) presaleWhitelist; // Pre-sale Whitelist

    event Buy(address indexed sender, uint eth, uint fbt);
    event Withdraw(address indexed sender, address to, uint eth);
    event AllocateTokens(address indexed sender);

    function PDATAToken(address depositAddress) {
        /*
            Initialize the contract with a sane set of owners
        */
        founder = msg.sender;  // Allocate the founder address as a usable address separate from deposit.
        deposit = depositAddress;  // Store the deposit address.
    }

    function setETHUSDRate(uint centsPerEthInput) public {
        /*
            Sets the current ETH/USD Exchange rate in cents.  This modifies the token price in Wei.
        */
        require(msg.sender == founder);
        centsPerEth = centsPerEthInput;
    }

    /*
        Gets the current state of the contract based on the block number involved in the current transaction.
    */
    function getCurrentState() constant public returns (State) {

        if(halted) return State.Halted;
        else if(block.timestamp < publicSaleStart) return State.PreSale;
        else if(block.timestamp > publicSaleStart && block.timestamp <= saleEnd) return State.Sale;
        else return State.Running;
    }

    /*
        Gets the current amount of bonus per purchase in percent.
    */
    function getCurrentBonusInPercent() constant public returns (uint) {
        State s = getCurrentState();
        if (s == State.Halted) revert();
        else if(s == State.PreSale) return 45;
        else if(s == State.Sale)
        {
            //TODO here
            uint bonus = 40 - ((block.timestamp - publicSaleStart) / (24 * 60 * 60))
            if bonus > 40 return 0;
            else return bonus;
        }
        else return 0;
    }

    /*
        Get the current price of the token in WEI.  This should be the weiPerEther/centsPerEth * centsPerToken
    */
    function getTokenPriceInWEI() constant public returns (uint){
        uint weiPerCent = safeDiv(weiPerEther, centsPerEth);
        return safeMul(weiPerCent, centsPerToken);
    }

    /*
        Entry point for purchasing for one's self.
    */
    function buy() payable public {
        buyRecipient(msg.sender);
    }

    /*
        Main purchasing function for the contract
        1. Should validate the current state, from the getCurrentState() function
        2. Should only allow the founder to order during the pre-sale
        3. Should correctly calculate the values to be paid out during different stages of the contract.
    */
    function buyRecipient(address recipient) payable public {
        State current_state = getCurrentState(); // Get the current state of the contract.
        uint usdCentsRaise = safeDiv(safeMul(msg.value, centsPerEth), weiPerEther); // Get the current number of cents raised by the payment.

        if(current_state == State.PreSale)
        {
            require (presaleWhitelist[msg.sender] > 0);
            raisePreSale = safeAdd(raisePreSale, usdCentsRaise); //add current raise to pre-sell amount
            require(raisePreSale < capPreSale && usdCentsRaise < presaleWhitelist[msg.sender]); //ensure pre-sale cap, 15m usd * 100 so we have cents
            presaleWhitelist[msg.sender] = presaleWhitelist[msg.sender] - usdCentsRaise; // Remove the amount purchased from the pre-sale permitted for that user
        }
        else if (current_state == State.Sale)
        {
            //TODO here
            raiseDay1 = safeAdd(raiseDay1, usdCentsRaise); //add current raise to pre-sell amount
            require(raiseDay1 < (capDay1 - raisePreSale)); //ensure day 1 cap, which is lower by the amount we pre-sold
        }
        else revert();

        uint tokens = safeDiv(msg.value, getTokenPriceInWEI()); // Calculate number of tokens to be paid out
        uint bonus = safeDiv(safeMul(tokens, getCurrentBonusInPercent()), 100); // Calculate number of bonus tokens

        if (current_state == State.PreSale) {
            // Remove the extra 5% from the totalTokensCompany, in order to keep the 550m on track.
            totalTokensCompany = safeSub(totalTokensCompany, safeDiv(bonus, 4));
        }

        uint totalTokens = safeAdd(tokens, bonus);

        balances[recipient] = safeAdd(balances[recipient], totalTokens);
        totalSupply = safeAdd(totalSupply, totalTokens);

        deposit.transfer(msg.value); // Send deposited Ether to the deposit address on file.

        Buy(recipient, msg.value, totalTokens);
    }

    /*
        Allocate reserved and founders tokens based on the running time and state of the contract.
     */
    function allocateReserveAndFounderTokens() {
        require(msg.sender==founder);
        require(getCurrentState() == State.Running);
        uint tokens = 0;

        if(block.timestamp > saleEnd && !allocatedFounders)
        {
            allocatedFounders = true;
            tokens = totalTokensCompany;
            balances[founder] = safeAdd(balances[founder], tokens);
            totalSupply = safeAdd(totalSupply, tokens);
        }
        else if(block.timestamp > year1Unlock && !allocated1Year)
        {
            allocated1Year = true;
            tokens = safeDiv(totalTokensReserve, 4);
            balances[founder] = safeAdd(balances[founder], tokens);
            totalSupply = safeAdd(totalSupply, tokens);
        }
        else if(block.timestamp > year2Unlock && !allocated2Year)
        {
            allocated2Year = true;
            tokens = safeDiv(totalTokensReserve, 4);
            balances[founder] = safeAdd(balances[founder], tokens);
            totalSupply = safeAdd(totalSupply, tokens);
        }
        else if(block.timestamp > year3Unlock && !allocated3Year)
        {
            allocated3Year = true;
            tokens = safeDiv(totalTokensReserve, 4);
            balances[founder] = safeAdd(balances[founder], tokens);
            totalSupply = safeAdd(totalSupply, tokens);
        }
        else if(block.timestamp > year4Unlock && !allocated4Year)
        {
            allocated4Year = true;
            tokens = safeDiv(totalTokensReserve, 4);
            balances[founder] = safeAdd(balances[founder], tokens);
            totalSupply = safeAdd(totalSupply, tokens);
        }
        else revert();

        AllocateTokens(msg.sender);
    }

    /**
     * Emergency Stop ICO.
     *
     *  Applicable tests:
     *
     * - Test unhalting, buying, and succeeding
     */
    function halt() {
        require(msg.sender==founder);
        halted = true;
    }

    function unhalt() {
        require(msg.sender==founder);
        halted = false;
    }

    /*
        Change founder address (Controlling address for contract)
    */
    function changeFounder(address newFounder) {
        require(msg.sender==founder);
        founder = newFounder;
    }

    /*
        Change deposit address (Address to which funds are deposited)
    */
    function changeDeposit(address newDeposit) {
        require(msg.sender==founder);
        deposit = newDeposit;
    }

    /*
        Add people to the pre-sale whitelist
        Amount should be the value in USD that the purchaser is allowed to buy
        IE: 100 is $100 is 10000 cents.  The correct value to enter is 100
    */
    function addPresaleWhitelist(address toWhitelist, uint256 amount){
        require(msg.sender==founder && amount > 0);
        presaleWhitelist[toWhitelist] = amount * 100;
    }

    /**
     * ERC 20 Standard Token interface transfer function
     *
     * Prevent transfers until freeze period is over.
     *
     * Applicable tests:
     *
     * - Test restricted early transfer
     * - Test transfer after restricted period
     */
    function transfer(address _to, uint256 _value) returns (bool success) {
        require(block.timestamp > coinTradeStart);
        return super.transfer(_to, _value);
    }
    /**
     * ERC 20 Standard Token interface transfer function
     *
     * Prevent transfers until freeze period is over.
     */
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
        require(block.timestamp > coinTradeStart);
        return super.transferFrom(_from, _to, _value);
    }

    function() payable {
        buyRecipient(msg.sender);
    }

}
