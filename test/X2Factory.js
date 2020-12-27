const { expect, use } = require("chai")
const { solidity } = require("ethereum-waffle")
const { loadFixtures, contractAt } = require("./shared/fixtures")
const { maxUint256, expandDecimals, reportGasUsed, increaseTime, mineBlock } = require("./shared/utilities")
const { toChainlinkPrice } = require("./shared/chainlink")

use(solidity)

describe("X2Factory", function () {
  const provider = waffle.provider
  const [wallet, user0, user1] = provider.getWallets()
  let weth
  let factory
  let router
  let market
  let priceFeed
  let feeToken

  beforeEach(async () => {
    const fixtures = await loadFixtures(provider)
    weth = fixtures.weth
    factory = fixtures.factory
    market = fixtures.market
    priceFeed = fixtures.priceFeed
    feeToken = fixtures.feeToken
  })

  it("inits", async () => {
    expect(await factory.feeToken()).eq(feeToken.address)
    expect(await factory.gov()).eq(wallet.address)
  })

  it("marketsLength", async () => {
    expect(await factory.marketsLength()).eq(1)
  })

  it("enableFreeMarketCreation", async () => {
    expect(await factory.freeMarketCreation()).eq(false)
    await expect(factory.connect(user0).createMarket(
      "X2:BULL",
      "X2:BEAR",
      weth.address,
      priceFeed.address,
      50000, // multiplierBasisPoints, 500%
      8000, // maxProfitBasisPoints, 80%
      50 // minDeltaBasisPoints, 0.5%
    )).to.be.revertedWith("X2Factory: forbidden")

    await expect(factory.connect(user0).enableFreeMarketCreation())
      .to.be.revertedWith("X2Factory: forbidden")

    await factory.enableFreeMarketCreation()
    expect(await factory.freeMarketCreation()).eq(true)
    expect(await factory.marketsLength()).eq(1)

    await factory.connect(user0).createMarket(
      "X2:BULL",
      "X2:BEAR",
      weth.address,
      priceFeed.address,
      50000, // multiplierBasisPoints, 500%
      8000, // maxProfitBasisPoints, 90%
      50 // minDeltaBasisPoints, 0.5%
    )

    expect(await factory.marketsLength()).eq(2)
  })

  it("createMarket", async () => {
    await expect(factory.connect(user0).createMarket(
      "X2:BULL",
      "X2:BEAR",
      weth.address,
      priceFeed.address,
      50000, // multiplierBasisPoints, 500%
      8000, // maxProfitBasisPoints, 90%
      50 // minDeltaBasisPoints, 0.5%
    )).to.be.revertedWith("X2Factory: forbidden")

    await factory.createMarket(
      "X2:BULL",
      "X2:BEAR",
      weth.address,
      priceFeed.address,
      50000, // multiplierBasisPoints, 500%
      8000, // maxProfitBasisPoints, 90%
      50 // minDeltaBasisPoints, 0.5%
    )
    expect(await factory.marketsLength()).eq(2)

    const marketAddress = await factory.markets(1)
    const market = await contractAt("X2Market", marketAddress)
    const bullToken = await contractAt("X2Token", await market.bullToken())
    const bearToken = await contractAt("X2Token", await market.bearToken())

    expect(await market.factory()).eq(factory.address)
    expect(await market.collateralToken()).eq(weth.address)
    expect(await market.priceFeed()).eq(priceFeed.address)
    expect(await market.multiplierBasisPoints()).eq(50000)
    expect(await market.maxProfitBasisPoints()).eq(8000)
    expect(await market.lastPrice()).eq(toChainlinkPrice(1000))

    expect(await bullToken.market()).eq(market.address)
    expect(await bullToken.name()).eq("X2:BULL")
    expect(await bullToken.symbol()).eq("X2:BULL")

    expect(await bearToken.market()).eq(market.address)
    expect(await bearToken.name()).eq("X2:BEAR")
    expect(await bearToken.symbol()).eq("X2:BEAR")

    await expect(market.initialize(
      factory.address,
      weth.address,
      weth.address,
      feeToken.address,
      priceFeed.address,
      50000, // multiplierBasisPoints, 500%
      8000, // maxProfitBasisPoints, 90%
      50 // minDeltaBasisPoints, 0.5%
    )).to.be.revertedWith("X2Market: already initialized")

    await expect(bullToken.initialize(factory.address, market.address, "X2:BULL"))
      .to.be.revertedWith("X2Token: already initialized")

    await expect(bearToken.initialize(factory.address, market.address, "X2:BEAR"))
      .to.be.revertedWith("X2Token: already initialized")
  })

  it("setGov", async () => {
    expect(await factory.gov()).eq(wallet.address)
    await expect(factory.connect(user0).setGov(user0.address))
      .to.be.revertedWith("X2Factory: forbidden")

    await factory.setGov(user0.address)
    expect(await factory.gov()).eq(user0.address)

    await factory.connect(user0).setGov(user1.address)
    expect(await factory.gov()).eq(user1.address)
  })

  it("setFeeReceiver", async () => {
    expect(await factory.feeReceiver()).eq(ethers.constants.AddressZero)
    await expect(factory.connect(user0).setFeeReceiver(user1.address))
      .to.be.revertedWith("X2Factory: forbidden")

    await factory.setFeeReceiver(user1.address)
    expect(await factory.feeReceiver()).eq(user1.address)
  })

  it("setFee", async () => {
    await expect(factory.setFee(market.address, 41))
      .to.be.revertedWith("X2Factory: fee exceeds allowed limit")

    await expect(factory.connect(user0).setFee(market.address, 40))
      .to.be.revertedWith("X2Factory: forbidden")

    expect(await factory.feeBasisPoints(market.address)).eq(0)

    await factory.setFee(market.address, 40)
    expect(await factory.feeBasisPoints(market.address)).eq(40)
  })

  it("getFee", async () => {
    expect(await factory.getFee(market.address, 20000)).eq(0)
    await factory.setFee(market.address, 30)
    expect(await factory.getFee(market.address, 20000)).eq(0)
    await factory.setFeeReceiver(user1.address)
    expect(await factory.getFee(market.address, 20000)).eq(60)
  })
})
