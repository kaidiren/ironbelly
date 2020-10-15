import React, { Component } from 'react'
import { Alert } from 'react-native'
import { isIphoneX } from 'react-native-iphone-x-helper'
import { connect } from 'react-redux'
import FormTextInput from 'src/components/FormTextInput'
// @ts-ignore
import { KeyboardAwareScrollView } from 'react-native-keyboard-aware-scroll-view'
import { State as ReduxState, Error, Navigation } from 'src/common/types'
import { Wrapper, UnderHeaderBlock, Spacer, FlexGrow } from 'src/common'
import { Button, Text } from 'src/components/CustomFont'
type Props = {
  error: Error
  navigation: Navigation
  setPassword: (password: string) => void
  password: string
  setConfirmPassword: (confirmPassword: string) => void
  confirmPassword: string
  newWallet: boolean
  setIsNew: (value: boolean) => void
}
type State = {}

class NewPassword extends Component<Props, State> {
  UNSAFE_componentWillMount() {
    const { navigation, route, setIsNew } = this.props

    if (route?.params) {
      setIsNew(route.params.isNew)
    }
  }

  _confirmPassword = null
  _scrollView = null

  render() {
    const {
      newWallet,
      password,
      setPassword,
      confirmPassword,
      setConfirmPassword,
      navigation,
    } = this.props
    return (
      <FlexGrow>
        <KeyboardAwareScrollView
          style={{
            flexGrow: 1,
          }}
          keyboardVerticalOffset={isIphoneX() ? 88 : 64}
          keyboardShouldPersistTaps="handled"
          keyboardOpeningTime={0}
          getTextInputRefs={() => [this._confirmPassword]}
          innerRef={(view) => {
            this._scrollView = view
          }}>
          <Wrapper>
            <UnderHeaderBlock>
              <Text>Choose a strong password to protect your new wallet.</Text>
            </UnderHeaderBlock>
            <Spacer />
            <FormTextInput
              testID="Password"
              returnKeyType={'next'}
              autoFocus={true}
              secureTextEntry={true}
              onChange={setPassword}
              onSubmitEditing={() => {
                if (this._confirmPassword) {
                  this._confirmPassword.focus()
                }
              }}
              value={password}
              title="Password"
            />
            <Spacer />
            <FormTextInput
              testID="ConfirmPassword"
              returnKeyType={'done'}
              autoFocus={false}
              secureTextEntry={true}
              getRef={(input) => {
                this._confirmPassword = input
              }}
              onChange={setConfirmPassword}
              onFocus={(e) => {
                if (this._scrollView) {
                  setTimeout(() => {
                    if (this._scrollView) {
                      this._scrollView.scrollToEnd()
                    }
                  }, 100)
                }
              }}
              value={confirmPassword}
              title="Confirm password"
            />
            <FlexGrow />
            <Spacer />
            <Button
              testID="SubmitPassword"
              title={'Continue'}
              onPress={() => {
                if (newWallet) {
                  navigation.navigate('ShowPaperKey')
                } else {
                  Alert.alert(
                    'Paper key',
                    'How many words in your paper key?',
                    [
                      {
                        text: '12',
                        onPress: () => {
                          navigation.navigate('VerifyPaperKey', {
                            title: 'Paper key',
                            wordsCount: 12,
                          })
                        },
                      },
                      {
                        text: '24',
                        onPress: () => {
                          navigation.navigate('VerifyPaperKey', {
                            title: 'Paper key',
                            wordsCount: 24,
                          })
                        },
                      },
                    ],
                  )
                }
              }}
              disabled={!(password && password === confirmPassword)}
            />
            <Spacer />
          </Wrapper>
        </KeyboardAwareScrollView>
      </FlexGrow>
    )
  }
}

const mapStateToProps = (state: ReduxState) => ({
  settings: state.settings,
  error: state.tx.txCreate.error,
  password: state.wallet.walletInit.password,
  newWallet: state.wallet.walletInit.isNew,
  confirmPassword: state.wallet.walletInit.confirmPassword,
})

const mapDispatchToProps = (dispatch, ownProps) => ({
  setPassword: (password) => {
    dispatch({
      type: 'WALLET_INIT_SET_PASSWORD',
      password,
    })
  },
  setConfirmPassword: (confirmPassword) => {
    dispatch({
      type: 'WALLET_INIT_SET_CONFIRM_PASSWORD',
      confirmPassword,
    })
  },
  setIsNew: (value) => {
    dispatch({
      type: 'WALLET_INIT_SET_IS_NEW',
      value,
    })
  },
})

export default connect(mapStateToProps, mapDispatchToProps)(NewPassword)
