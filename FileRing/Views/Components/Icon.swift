//
//  Icon.swift
//  PopUp
//
//  Created by Cosmos on 01/11/2025.
//

import SwiftUI

struct Icon: View {
    var body: some View {
        GeometryReader{ proxy in
            HStack(spacing:0){
                Circle()
                    .fill(.blue)
                    .frame(width: proxy.size.height, height: proxy.size.height)

                VStack(spacing: proxy.size.height/10){
                    Capsule()
                        .fill(.blue)
                    Capsule()
                        .fill(.blue)
                    Capsule()
                        .fill(.blue)
                }
                .padding(.vertical, proxy.size.height/100*3)
                .padding(.leading, proxy.size.height/8)
            }
        }
        .aspectRatio(1.8/1, contentMode: .fit)
    }
}

struct IconWithBackground: View {
    var body: some View {
        GeometryReader{ proxy in
            ZStack{
                RoundedRectangle(cornerRadius: proxy.size.height/4)
                    .fill(.white)
                    .shadow(radius: proxy.size.height/10)
                Icon()
                    .padding(proxy.size.height/6)
            }
        }
        .aspectRatio(1, contentMode: .fit)

    }
}

#Preview {
    ZStack{
        Color.gray

        IconWithBackground()
            .frame(height: 100)


    }
}
