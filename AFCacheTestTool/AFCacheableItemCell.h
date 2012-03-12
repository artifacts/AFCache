//
//  AFCachableItemCell.h
//  AFCacheTestTool
//
//  Created by Michael Markowski on 12.03.12.
//  Copyright (c) 2012 artifacts Software GmbH & Co. KG. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface AFCacheableItemCell : UITableViewCell

@property (strong, nonatomic) IBOutlet UILabel *keyLabel;
@property (strong, nonatomic) IBOutlet UILabel *valueLabel;

@end
