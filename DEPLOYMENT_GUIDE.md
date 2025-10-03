# Create Profile

`aptos init --profile resort-maker-2`

# Show private key

`aptos config show-private-key --profile new-resort-2`

# Compile

`aptos move compile --named-addresses launchpad_addr=default,initial_creator_addr=default`

### ex 2

`aptos move compile --named-addresses launchpad_addr=resort-maker-2,initial_creator_addr=resort-maker-2`

# Deploy on Local Network

`aptos move publish --named-addresses launchpad_addr=default,initial_creator_addr=default --profile local`

# Deploy on Testnet

`aptos move publish --named-addresses launchpad_addr=default,initial_creator_addr=default --profile default`

`aptos move publish --named-addresses launchpad_addr=resort-maker-2,initial_creator_addr=resort-maker-2 --profile resort-maker-2`

# Deploy on Mainnet

`aptos move publish --named-addresses launchpad_addr=default,initial_creator_addr=default --profile mainnet`
