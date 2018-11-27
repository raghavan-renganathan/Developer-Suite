//
//  DashboardTabBarController.swift
//  Developer Suite
//
//  Created by RAGHAVAN RENGANATHAN on 11/11/18.
//  Copyright © 2018 RAGHAVAN RENGANATHAN. All rights reserved.
//

import UIKit
import FirebaseAuth

class DashboardTabBarController: UITabBarController {
    
    // Mark: Properties
    var currentUser: UserMO!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    // Mark: Private Methods
    
    private func navigateToLoginScreen() {
        self.performSegue(withIdentifier: "NavigateToLoginScreen", sender: self)
    }
    
    // Mark: Actions
    @IBAction func doSignOut(_ sender: Any) {
        do {
            try Auth.auth().signOut()
            navigateToLoginScreen()
        } catch {
            Utils.log("Unable to signout user.")
        }
    }
}