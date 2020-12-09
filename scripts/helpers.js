async function sendTxn(txnPromise, label) {
  const txn = await txnPromise
  console.info(`Sending ${label}...`)
  await txn.wait()
  console.info("... Sent!")
  return txn
}

async function deployContract(name, args, label) {
  let info = name
  if (label) { info = name + ":" + label }
  const contractFactory = await ethers.getContractFactory(name)
  const contract = await contractFactory.deploy(...args)
  console.info(`Deploying ${info} ${args} to ${contract.address}...`)
  await contract.deployTransaction.wait()
  console.info("... Completed!")
  return contract
}

async function contractAt(name, address) {
  const contractFactory = await ethers.getContractFactory(name)
  return await contractFactory.attach(address)
}

module.exports = { sendTxn, deployContract, contractAt }
