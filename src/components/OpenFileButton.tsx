/**
 * Copyright 2020 Ironbelly Devs
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import React from 'react'
import colors from 'src/common/colors'
import { TouchableOpacity, StyleSheet, Platform } from 'react-native'
import FontAwesome5Icons from 'react-native-vector-icons/FontAwesome5'
import { Text } from 'src/components/CustomFont'
import DocumentPicker from 'react-native-document-picker'

function OpenFileButton({ callback }: { callback: (uri: string) => void }) {
  const openFile = async () => {
    try {
      const { uri } = await DocumentPicker.pick({
        type: [DocumentPicker.types.allFiles],
      })
      callback(uri)
    } catch (e) {
      console.error(e)
    }
  }

  return (
    <TouchableOpacity onPress={openFile}>
      <Text style={styles.slatepackHeaderCopy}>
        Open{' '}
        <FontAwesome5Icons
          name="folder-open"
          size={18}
          style={{
            color: colors.link,
          }}
        />
      </Text>
    </TouchableOpacity>
  )
}

const styles = StyleSheet.create({
  slatepackHeaderCopy: {
    fontWeight: Platform.select({ android: '700', ios: '500' }),
    color: colors.link,
    fontSize: 16,
  },
})

export default OpenFileButton