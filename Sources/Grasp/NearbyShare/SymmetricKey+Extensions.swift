//
//  SymmetricKey+Extensions.swift
//  Grasp
//
//  Created by Elmee on 10/08/26.
//  Copyright © 2026 KaMy Studio. All rights reserved.
//

import Foundation
import CryptoKit

extension SymmetricKey{
	func data() -> Data{
		return withUnsafeBytes({return Data(bytes: $0.baseAddress!, count: $0.count)})
	}
}
