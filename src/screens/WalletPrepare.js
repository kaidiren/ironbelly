// @flow
//
// Copyright 2019 Ivan Sorokin.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import React, { Component, Fragment } from 'react'
import { ActivityIndicator } from 'react-native'
import { connect } from 'react-redux'
import styled from 'styled-components/native'

import { Spacer, LoaderView } from 'common'
import colors from 'common/colors'
import { type State as ReduxState, type Navigation } from 'common/types'
import { Text, Button } from 'components/CustomFont'
import { RECOVERY_LIMIT, type WalletInitState } from 'modules/wallet'
import { AnimatedCircularProgress } from 'react-native-circular-progress'
import KeepAwake from 'react-native-keep-awake'

type Props = WalletInitState & {
  navigation: Navigation,
  recoverWallet: (startIndex: number) => void,
}
type State = {}

const StatusText = styled(Text)`
  font-size: 24;
`
const ProgressText = styled(Text)`
  font-size: 28;
`

const Wrapper = styled(LoaderView)`
  padding: 16px;
`

class WalletPrepare extends Component<Props, State> {
  static navigationOptions = {
    header: null,
  }

  state = {}

  componentDidMount() {
    const { recoverWallet, created, lastRetrievedIndex, inProgress } = this.props
    if (!created && !inProgress && lastRetrievedIndex) {
      recoverWallet(lastRetrievedIndex + 1)
    }
  }

  componentDidUpdate(prevProps) {
    if (this.props.error.message && !prevProps.error.message) {
      this.props.navigation.goBack()
    }
    const { recoverWallet, created, lastRetrievedIndex, inProgress } = this.props
    if (!created && !inProgress && lastRetrievedIndex) {
      recoverWallet(lastRetrievedIndex + 1)
    }
  }

  render() {
    const { navigation, created, isNew, progress } = this.props
    return (
      <Wrapper>
        <KeepAwake />
        {(!created && (
          <Fragment>
            {(!isNew && (
              <Fragment>
                <AnimatedCircularProgress
                  style={{ alignSelf: 'center' }}
                  size={120}
                  backgroundWidth={4}
                  width={6}
                  fill={progress}
                  tintColor={colors.black}
                  rotation={0}
                  onAnimationComplete={() => console.log('onAnimationComplete')}
                  backgroundColor={colors.primary}
                >
                  {fill => <ProgressText>{`${progress}%`}</ProgressText>}
                </AnimatedCircularProgress>
                <Spacer />
                <StatusText style={{ textAlign: 'center' }}>Recovery in progress</StatusText>
              </Fragment>
            )) || <ActivityIndicator size="large" color={colors.primary} />}
          </Fragment>
        )) || (
          <Fragment>
            <StatusText>Your wallet was succesfully created!</StatusText>
            <Spacer />
            <Button
              testID="ShowMeButton"
              title="Show me"
              disabled={false}
              onPress={() => {
                navigation.navigate('Main')
              }}
            />
          </Fragment>
        )}
      </Wrapper>
    )
  }
}

const mapStateToProps = (state: ReduxState) => ({
  ...state.wallet.walletInit,
})

const mapDispatchToProps = (dispatch, ownProps) => ({
  recoverWallet: startIndex => {
    dispatch({ type: 'WALLET_RECOVERY_REQUEST', startIndex, limit: RECOVERY_LIMIT })
  },
})

export default connect(
  mapStateToProps,
  mapDispatchToProps
)(WalletPrepare)
